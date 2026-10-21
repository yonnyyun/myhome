-- 기준일 가용자금의 항목별 금액. 기존 잔액과 거래는 보존.
alter table public.onjip_settings add column funds jsonb not null default '[]'::jsonb
 check(jsonb_typeof(funds)='array' and jsonb_array_length(funds)<=100);
update public.onjip_settings set funds=jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'name','기존 가용금액','amount',balance)) where balance<>0;

-- 기존 원자적 저장/조회 로직은 비공개 스키마에서 재사용.
alter function public.onjip_save_home(uuid,bigint,jsonb) set schema onjip_private;
alter function public.onjip_load_home() set schema onjip_private;
revoke all on function onjip_private.onjip_save_home(uuid,bigint,jsonb),onjip_private.onjip_load_home() from public,anon,authenticated;

create function onjip_private.save_funds(p_home uuid,p_version bigint,p_state jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare v_funds jsonb; v_old public.onjip_settings; v_item jsonb; v_total numeric:=0; v_next bigint; v_current bigint;
begin
 if not onjip_private.is_member(p_home) then raise exception 'ACCESS_DENIED'; end if;
 select version into v_current from public.onjip_households where id=p_home for update;
 if not onjip_private.is_member(p_home) then raise exception 'ACCESS_DENIED'; end if;
 if v_current is distinct from p_version then raise exception 'VERSION_CONFLICT'; end if;
 select * into v_old from public.onjip_settings where household_id=p_home;
 if p_state->'settings' ? 'funds' then
  v_funds:=p_state->'settings'->'funds';
 else
  -- 배포 전환 중 구버전 클라이언트와 기존 JSON 백업 호환.
  if (p_state->'settings'->>'balance')::numeric=v_old.balance then v_funds:=v_old.funds;
  else v_funds:=jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'name','기존 가용금액','amount',(p_state->'settings'->>'balance')::numeric)); end if;
 end if;
 if jsonb_typeof(v_funds) is distinct from 'array' or jsonb_array_length(v_funds)>100 then raise exception 'INVALID_FUNDS'; end if;
 for v_item in select value from jsonb_array_elements(v_funds) loop
  if jsonb_typeof(v_item) is distinct from 'object' or jsonb_typeof(v_item->'id') is distinct from 'string' or jsonb_typeof(v_item->'name') is distinct from 'string' or length(trim(v_item->>'name')) not between 1 and 100 or jsonb_typeof(v_item->'amount') is distinct from 'number' then raise exception 'INVALID_FUNDS'; end if;
  perform (v_item->>'id')::uuid;
  if (v_item->>'amount')::numeric<>trunc((v_item->>'amount')::numeric) or abs((v_item->>'amount')::numeric)>100000000000 then raise exception 'INVALID_FUNDS_AMOUNT'; end if;
  v_total:=v_total+(v_item->>'amount')::numeric;
 end loop;
 if abs(v_total)>100000000000 then raise exception 'INVALID_FUNDS_TOTAL'; end if;
 if (select count(distinct (x->>'id')::uuid) from jsonb_array_elements(v_funds) x)<>jsonb_array_length(v_funds) then raise exception 'DUPLICATE_FUNDS_ID'; end if;
 -- 합계는 클라이언트 입력을 신뢰하지 않고 DB에서 계산.
 p_state:=jsonb_set(p_state,'{settings,balance}',to_jsonb(v_total::bigint));
 v_next:=onjip_private.onjip_save_home(p_home,p_version,p_state);
 update public.onjip_settings set funds=v_funds where household_id=p_home;
 return v_next;
end; $$;
create function onjip_private.load_funds() returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_snapshot jsonb; v_funds jsonb;
begin
 v_snapshot:=onjip_private.onjip_load_home();
 if v_snapshot is null then return null; end if;
 select funds into v_funds from public.onjip_settings where household_id=(v_snapshot->>'id')::uuid;
 return jsonb_set(v_snapshot,'{state,settings,funds}',v_funds);
end; $$;
create function public.onjip_save_home(p_home uuid,p_version bigint,p_state jsonb) returns bigint
language sql security invoker set search_path='' as $$select onjip_private.save_funds(p_home,p_version,p_state);$$;
create function public.onjip_load_home() returns jsonb
language sql security invoker set search_path='' as $$select onjip_private.load_funds();$$;
revoke all on function onjip_private.save_funds(uuid,bigint,jsonb),onjip_private.load_funds(),public.onjip_save_home(uuid,bigint,jsonb),public.onjip_load_home() from public,anon;
grant execute on function onjip_private.save_funds(uuid,bigint,jsonb),onjip_private.load_funds(),public.onjip_save_home(uuid,bigint,jsonb),public.onjip_load_home() to authenticated;
