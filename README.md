# 온집 — 우리 집 돈의 흐름

가계의 월별 수입·소비·가용금액과 자금 소진 시점을 관리하는 모바일 웹사이트입니다.

## 구성
Vercel 정적 호스팅 + Supabase Auth/Postgres. 별도 서버 프로세스나 관리자 비밀키 없이 공개 클라이언트 키와 가족별 접근 제어로 동작합니다.

## 주요 기능
- 이메일 회원가입·로그인·비밀번호 재설정·로그아웃
- 빈 가계부 시작, 가족 일회용 초대코드 및 소유자의 접근 해제
- 월별 수입·소비 등록·수정·삭제, 카테고리 필터, 고정지출
- 월말 잔액 24개월 예측과 생활비 시나리오
- 브라우저 한글 OCR → 거래 후보 검토 → 저장
- JSON 백업/복원, 동시 저장 충돌 방지, 30초 주기 최신 데이터 조회

## 시작
온집에 회원가입한 후 이메일을 확인하고 로그인하세요. 새 가계부를 만든 뒤 설정에서 기준 잔액과 수입·지출 계획을 입력합니다. 가족은 새 가계부 대신 초대코드로 참여하세요.

자세한 설정·데이터 이전·권한·검증 범위는 [Supabase 연결 안내](docs/SUPABASE-SETUP.md)를 참고하세요.

## 로컬 실행
```sh
python3 -m http.server 5173
```
http://localhost:5173 으로 접속합니다. 거래는 연결된 Supabase에 저장되므로 로컬 실행도 실제 계정과 가계부를 사용합니다. 이메일 확인·비밀번호 재설정의 기본 복귀 주소는 운영 Vercel 주소입니다.

## 배포
Vercel에서 `yonnyyun/myhome`을 연결합니다. Framework **Other**, Build Command 비움, Output Directory **`.`**으로 설정합니다. `main` 브랜치를 자동 배포하도록 연결하면 새 커밋이 반영됩니다.

`supabase-config.js`에는 공개 Project URL·Publishable key·운영 사이트 주소만 있습니다. 관리자 비밀키와 DB 비밀번호를 소스에 추가하지 마세요. 다른 프로젝트에 설치할 때는 [초기 SQL](supabase/001_onjip.sql)을 먼저 적용해야 합니다.

## 파일
- index.html / style.css / app.js — 모바일 화면과 가계부 계산
- cloud.js — 인증, 가족 참여, 저장·조회 및 오류 복구
- supabase-config.js — 브라우저 공개 연결 설정
- supabase/001_onjip.sql — DB 테이블·RPC·RLS
- vendor/ — Supabase JS 2.118.0 및 MIT 라이선스
- fonts/ — Pretendard 가변 폰트 및 OFL 라이선스
- docs/ — PRD와 운영 안내

## 데이터 유의점
기존 localStorage 내역은 자동으로 업로드하지 않습니다. JSON 백업을 이용해 이전할 수 있으며 예시 데이터는 서버로 가져오지 않습니다. 금액은 원화 정수로 저장합니다. 예측은 월 단위이며 월중 입출금 순서를 반영하지 않습니다.

## 테스트
```sh
npm --prefix tests install
npm --prefix tests test
```
로컬 PostgreSQL 엔진과 DOM 모형에서 실행되며 실제 Supabase 계정이나 거래를 만들지 않습니다.
