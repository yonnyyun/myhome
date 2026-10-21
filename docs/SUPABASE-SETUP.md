# 온집 Supabase 연결

## 현재 구성
- 화면: Vercel 정적 사이트
- 로그인·회원가입·비밀번호 재설정: Supabase Auth
- 저장: Postgres의 onjip_households, onjip_members, onjip_settings, onjip_fixed, onjip_transactions
- 초대: 공개 API에서 직접 읽지 못하는 onjip_private.invites
- 공개 키는 supabase-config.js에 포함. 관리자 비밀키는 사용하지 않음
- Supabase JS 2.118.0 클라이언트 번들을 vendor/supabase.js에 포함

## 초기 설치
이미 적용한 프로젝트에서는 SQL을 다시 실행하지 마세요. 다른 프로젝트로 설치할 때는 Supabase SQL Editor에서 supabase/001_onjip.sql을 실행합니다. 기존 테이블을 삭제하지 않으며 동일 객체가 있으면 SQL이 실패합니다. 추후 변경은 별도 migration으로 적용하세요.

Authentication → URL Configuration:
- Site URL: https://myhome-two-liard.vercel.app
- Redirect URLs: https://myhome-two-liard.vercel.app/

이메일 회원가입을 사용합니다. 이메일 확인 링크를 누르고 로그인하세요. Supabase 기본 메일 서비스는 실제 사용자에게 보내는 범위·발송량이 제한되어 있으므로 가족 이메일에 확인 메일이 오지 않으면 Authentication의 메일 설정에서 사용자 SMTP를 구성하세요. 실제 가입·메일 도착 여부는 본인 계정으로 확인해야 합니다.

## 사용 시작
1. 온집에서 회원가입, 이메일 확인, 로그인합니다.
2. 첫 사용자는 ‘새 가계부 만들기’를 선택합니다. 예시 없이 빈 가계부를 생성합니다.
3. 설정에서 기준일 시작 잔액·월 수입·변동지출·목표 월을 입력합니다.
4. 가족을 초대하려면 소유자 계정으로 설정 → 가족 초대코드 만들기.
5. 가족은 별도 회원가입·로그인 후 새 가계부를 만들지 말고 ‘가족 가계부에 참여하기’에 코드를 입력합니다.

초대코드는 24시간 유효한 일회용 코드입니다. 새 코드 생성 시 이전 미사용 코드는 만료됩니다. 자동 이메일 발송은 하지 않습니다. 사용자당 가계부 하나만 참여할 수 있으며 기존 가계부 간 병합·탈퇴 UI는 현재 지원하지 않습니다. 소유자는 가족 구성원 관리에서 접근을 해제할 수 있습니다.

## 기존 브라우저 데이터
이전 localStorage 가계부는 자동 업로드·삭제하지 않습니다. 이전 버전에서 JSON 백업을 받은 다음 새 버전 설정의 백업 불러오기로 가져오세요. 예시 데이터는 가져오지 않습니다. 복원은 가족 전체의 가계부를 교체하므로 먼저 서버 데이터도 백업하세요. 예전 문자열 ID는 UUID로 변환하여 고정지출 연결을 유지합니다.

## 저장과 동기화
- 저장은 RPC 하나에서 설정·고정지출·거래를 원자적으로 갱신합니다.
- 한 번에 고정지출 1,000건, 거래 50,000건까지. 소규모 가족용 MVP이며 큰 거래량에서는 거래별 RPC·월별 페이지 조회로 확장해야 합니다.
- household 버전 잠금으로 다른 기기의 선행 변경을 덮어쓰지 않습니다.
- 충돌 시 최신 데이터를 불러오고 미저장 사본을 메모리에 보관합니다. 설정에서 백업할 수 있으며 탭을 닫으면 미저장 사본은 사라집니다.
- 네트워크 실패 시 성공으로 표시하지 않고 화면 상태를 마지막 저장 상태로 되돌립니다.
- 30초마다 또는 창으로 복귀 시 최신 데이터를 조회합니다. 입력 중·저장 중·내역 모달 열림 중에는 자동 갱신하지 않습니다. 설정의 최신 데이터 불러오기로 수동 갱신할 수 있습니다. WebSocket 즉시 동기화는 사용하지 않습니다.
- 인증 세션은 Supabase 클라이언트가 브라우저에 보관합니다. 거래 데이터는 별도로 localStorage에 저장하지 않습니다.

## 접근 권한
- 로그인하지 않은 사용자는 가계부 조회·RPC 실행 불가.
- 가족 구성원만 자신의 가계부 읽기 가능. 직접 테이블 쓰기는 허용하지 않습니다.
- 저장 RPC는 auth.uid()와 구성원 여부, 데이터 유효성, 예상 버전을 검사합니다.
- 초대코드 생성과 구성원 접근 해제는 소유자 전용입니다.
- 함수는 고정된 빈 search_path를 사용하며 임의 SQL을 실행하지 않습니다.
- 개인별 수정 기록·감사 로그는 후속 범위입니다. 현재 가족은 동등하게 거래와 설정을 수정할 수 있습니다.

Supabase Security Advisor가 authenticated SECURITY DEFINER RPC를 경고하는 것은 의도된 API 구성입니다. 모든 RPC는 위 권한 검사를 수행하며 anon/PUBLIC의 실행 권한은 회수했습니다. invites의 ‘RLS enabled, no policy’는 직접 접근을 전부 거부하도록 의도한 구성입니다.
참고: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
참고: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

## 검증 범위
- 로컬 PostgreSQL(PGlite): 테이블 생성, 저장·조회, 금액 검증 롤백, 버전 충돌, 가족 격리, 일회용 초대, 소유자 권한, 구성원 해제, 익명 차단.
- 실제 Supabase: 임시 사용자를 한 트랜잭션 안에서 생성해 저장·조회·충돌·RLS·초대를 검사한 뒤 전체 롤백. 검증 데이터는 남기지 않음.
- 프런트 DOM: 로그인 차단 화면, 빈 가계부 생성, 거래 저장·조회, 네트워크 실패 복구, 충돌 사본 보관, 로그아웃 시 데이터 제거, 가입·재설정 폼.
- 실제 브라우저: 로그인·회원가입 화면, 폰트 및 폼 표시.
- 본인 이메일의 실제 가입·확인 메일 수신과 두 실제 기기의 로그인은 사용자가 완료해야 합니다.
