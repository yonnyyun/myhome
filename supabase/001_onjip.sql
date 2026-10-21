-- 온집: Supabase SQL Editor에서 실행. 기존 객체는 삭제하지 않습니다.
-- 각 사용자당 가계부 1개. 읽기는 RLS, 쓰기는 인증·버전 검사를 거치는 RPC만 허용.
create schema if not exists onjip_private;
revoke all on schema onjip_private from public, anon, authenticated;

create table public.onjip_households (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(trim(name)) between 1 and 60),
 owner_id uuid not null references auth.users(id),
 version bigint not null default 0 check(version>=0),
 created_at timestamptz not null default now()
);
create table public.onjip_members (
 household_id uuid not null references public.onjip_households(id) on delete cascade,
 user_id uuid not null unique references auth.users(id) on delete cascade,
 role text not null check(role in ('owner','editor')),
 primary key(household_id,user_id)
);
create table public.onjip_settings (
 household_id uuid primary key references public.onjip_households(id) on delete cascade,
 start_date date not null,
 balance bigint not null check(balance between -100000000000 and 100000000000),
 income bigint not null check(income between 0 and 1000000000),
 variable bigint not null check(variable between 0 and 100000000),
 target text not null check(target ~ '^\d{4}-(0[1-9]|1[0-2])$')
);
create table public.onjip_fixed (
 household_id uuid not null references public.onjip_households(id) on delete cascade,
 id uuid not null,
 name text not null check(length(trim(name)) between 1 and 100),
 amount bigint not null check(amount between 1 and 1000000000),
 day integer not null check(day between 1 and 31),
 primary key(household_id,id)
);
create table public.onjip_transactions (
 household_id uuid not null references public.onjip_households(id) on delete cascade,
 id uuid not null,
 type text not null check(type in ('expense','income')),
 name text not null check(length(trim(name)) between 1 and 100),
 amount bigint not null check(amount between 1 and 100000000000),
 date date not null,
 category text not null check(length(category) between 1 and 100),
 memo text not null default '' check(length(memo)<=300),
 fixed_id uuid,
 primary key(household_id,id),
 foreign key(household_id,fixed_id) references public.onjip_fixed(household_id,id),
 check(fixed_id is null or type='expense')
);
create unique index onjip_fixed_paid_once on public.onjip_transactions
 (household_id,fixed_id,extract(year from date),extract(month from date)) where fixed_id is not null;
create index onjip_transactions_month on public.onjip_transactions(household_id,date);
create table onjip_private.invites (
 token text primary key,
 household_id uuid not null references public.onjip_households(id) on delete cascade,
 expires_at timestamptz not null,
 used_by uuid references auth.users(id)
);
alter table onjip_private.invites enable row level security;
revoke all on onjip_private.invites from public,anon,authenticated;

create function onjip_private.is_member(p_home uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.onjip_members where household_id=p_home and user_id=auth.uid());
$$;
revoke all on function onjip_private.is_member(uuid) from public,anon;
grant usage on schema onjip_private to authenticated;
grant execute on function onjip_private.is_member(uuid) to authenticated;

alter table public.onjip_households enable row level security;
alter table public.onjip_members enable row level security;
alter table public.onjip_settings enable row level security;
alter table public.onjip_fixed enable row level security;
alter table public.onjip_transactions enable row level security;
create policy member_read on public.onjip_households for select to authenticated using(onjip_private.is_member(id));
create policy member_read on public.onjip_members for select to authenticated using(onjip_private.is_member(household_id));
create policy member_read on public.onjip_settings for select to authenticated using(onjip_private.is_member(household_id));
create policy member_read on public.onjip_fixed for select to authenticated using(onjip_private.is_member(household_id));
create policy member_read on public.onjip_transactions for select to authenticated using(onjip_private.is_member(household_id));
revoke all on public.onjip_households,public.onjip_members,public.onjip_settings,public.onjip_fixed,public.onjip_transactions from anon,authenticated;
grant select on public.onjip_households,public.onjip_members,public.onjip_settings,public.onjip_fixed,public.onjip_transactions to authenticated;

create function public.onjip_create_home(p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 select household_id into v_id from public.onjip_members where user_id=auth.uid();
 if v_id is not null then return v_id; end if;
 insert into public.onjip_households(name,owner_id) values(trim(p_name),auth.uid()) returning id into v_id;
 insert into public.onjip_members values(v_id,auth.uid(),'owner');
 insert into public.onjip_settings values(v_id,v_today,0,0,0,to_char(v_today+interval '8 months','YYYY-MM'));
 return v_id;
end; $$;

create function public.onjip_load_home() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_home public.onjip_households; v_role text; v_setting jsonb; v_fixed jsonb; v_tx jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 select h.* into v_home from public.onjip_households h join public.onjip_members m on m.household_id=h.id where m.user_id=auth.uid() for share of h;
 if not found then return null; end if;
 if not onjip_private.is_member(v_home.id) then raise exception 'ACCESS_DENIED'; end if;
 select role into v_role from public.onjip_members where household_id=v_home.id and user_id=auth.uid();
 select jsonb_build_object('start',start_date,'balance',balance,'income',income,'variable',variable,'target',target) into v_setting from public.onjip_settings where household_id=v_home.id;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'amount',amount,'day',day) order by day,id),'[]'::jsonb) into v_fixed from public.onjip_fixed where household_id=v_home.id;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'type',type,'name',name,'amount',amount,'date',date,'category',category,'memo',memo,'fixedId',coalesce(fixed_id::text,'')) order by date,id),'[]'::jsonb) into v_tx from public.onjip_transactions where household_id=v_home.id;
 return jsonb_build_object('id',v_home.id,'name',v_home.name,'role',v_role,'version',v_home.version,'state',jsonb_build_object('demo',false,'settings',v_setting,'fixed',v_fixed,'transactions',v_tx));
end; $$;

create function public.onjip_save_home(p_home uuid,p_version bigint,p_state jsonb) returns bigint language plpgsql security definer set search_path='' as $$
declare v_version bigint; v_s jsonb; x jsonb;
begin
 if not onjip_private.is_member(p_home) then raise exception 'ACCESS_DENIED'; end if;
 select version into v_version from public.onjip_households where id=p_home for update;
 if not onjip_private.is_member(p_home) then raise exception 'ACCESS_DENIED'; end if;
 if v_version is distinct from p_version then raise exception 'VERSION_CONFLICT'; end if;
 if jsonb_typeof(p_state) is distinct from 'object' or jsonb_typeof(p_state->'settings') is distinct from 'object' or jsonb_typeof(p_state->'fixed') is distinct from 'array' or jsonb_typeof(p_state->'transactions') is distinct from 'array' then raise exception 'INVALID_DATA'; end if;
 if jsonb_array_length(p_state->'fixed')>1000 or jsonb_array_length(p_state->'transactions')>50000 or (p_state->>'demo')::boolean is true then raise exception 'INVALID_DATA'; end if;
 v_s:=p_state->'settings';
 if (v_s->>'start')::date>(now() at time zone 'Asia/Seoul')::date then raise exception 'INVALID_START_DATE'; end if;
 foreach x in array array[v_s->'balance',v_s->'income',v_s->'variable'] loop
  if jsonb_typeof(x) is distinct from 'number' or (x::text)::numeric<>trunc((x::text)::numeric) then raise exception 'INVALID_AMOUNT'; end if;
 end loop;
 for x in select value from jsonb_array_elements(p_state->'fixed') loop
  if jsonb_typeof(x->'amount') is distinct from 'number' or (x->>'amount')::numeric<>trunc((x->>'amount')::numeric) or jsonb_typeof(x->'day') is distinct from 'number' or (x->>'day')::numeric<>trunc((x->>'day')::numeric) then raise exception 'INVALID_AMOUNT'; end if;
 end loop;
 for x in select value from jsonb_array_elements(p_state->'transactions') loop
  if jsonb_typeof(x->'amount') is distinct from 'number' or (x->>'amount')::numeric<>trunc((x->>'amount')::numeric) then raise exception 'INVALID_AMOUNT'; end if;
 end loop;
 update public.onjip_settings set start_date=(v_s->>'start')::date,balance=(v_s->>'balance')::bigint,income=(v_s->>'income')::bigint,variable=(v_s->>'variable')::bigint,target=v_s->>'target' where household_id=p_home;
 delete from public.onjip_transactions where household_id=p_home;
 delete from public.onjip_fixed where household_id=p_home;
 insert into public.onjip_fixed(household_id,id,name,amount,day)
 select p_home,(e->>'id')::uuid,e->>'name',(e->>'amount')::bigint,(e->>'day')::integer from jsonb_array_elements(p_state->'fixed') e;
 insert into public.onjip_transactions(household_id,id,type,name,amount,date,category,memo,fixed_id)
 select p_home,(e->>'id')::uuid,e->>'type',e->>'name',(e->>'amount')::bigint,(e->>'date')::date,e->>'category',coalesce(e->>'memo',''),nullif(e->>'fixedId','')::uuid from jsonb_array_elements(p_state->'transactions') e;
 update public.onjip_households set version=version+1 where id=p_home returning version into v_version;
 return v_version;
end; $$;

create function public.onjip_create_invite(p_home uuid) returns text language plpgsql security definer set search_path='' as $$
declare v_token text;
begin
 if not exists(select 1 from public.onjip_members where household_id=p_home and user_id=auth.uid() and role='owner') then raise exception 'OWNER_REQUIRED'; end if;
 -- 새 코드 발급 시 이전 미사용 코드는 모두 만료. 코드 자체를 URL에 싣지 않음.
 update onjip_private.invites set expires_at=now() where household_id=p_home and used_by is null;
 v_token:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');
 insert into onjip_private.invites values(v_token,p_home,now()+interval '1 day',null);
 return v_token;
end; $$;
create function public.onjip_join_home(p_token text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_inv onjip_private.invites;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if exists(select 1 from public.onjip_members where user_id=auth.uid()) then raise exception 'ALREADY_MEMBER'; end if;
 select * into v_inv from onjip_private.invites where token=lower(trim(p_token)) and used_by is null and expires_at>now() for update;
 if not found then raise exception 'INVALID_INVITE'; end if;
 insert into public.onjip_members values(v_inv.household_id,auth.uid(),'editor');
 update onjip_private.invites set used_by=auth.uid() where token=v_inv.token;
 return v_inv.household_id;
end; $$;
create function public.onjip_revoke_member(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_home uuid;
begin
 select household_id into v_home from public.onjip_members where user_id=auth.uid() and role='owner';
 if v_home is null then raise exception 'OWNER_REQUIRED'; end if;
 perform 1 from public.onjip_households where id=v_home for update;
 delete from public.onjip_members where household_id=v_home and user_id=p_user and role<>'owner';
 update public.onjip_households set version=version+1 where id=v_home;
end; $$;

revoke all on function public.onjip_create_home(text),public.onjip_load_home(),public.onjip_save_home(uuid,bigint,jsonb),public.onjip_create_invite(uuid),public.onjip_join_home(text),public.onjip_revoke_member(uuid) from public,anon;
grant execute on function public.onjip_create_home(text),public.onjip_load_home(),public.onjip_save_home(uuid,bigint,jsonb),public.onjip_create_invite(uuid),public.onjip_join_home(text),public.onjip_revoke_member(uuid) to authenticated;
