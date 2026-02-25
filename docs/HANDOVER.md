# 인수인계 문서 — Ansible 기반 서버 점검 자동화 시스템

**문서 버전**: 1.0  
**대상**: 본 프로젝트를 인수하여 유지·보수·개발을 진행할 개발자  
**범위**: 기능·코드 구조·환경 설정·배포·트러블슈팅

---

## 목차

0. [TL;DR (30분 온보딩/운영 치트시트)](#0-tldr-30분-온보딩운영-치트시트)
1. [개요 및 목적](#1-개요-및-목적)
2. [시스템 아키텍처 및 데이터 흐름](#2-시스템-아키텍처-및-데이터-흐름)
3. [API 서버 상세](#3-api-서버-상세)
4. [회원 및 권한](#4-회원-및-권한)
5. [관리자 콘솔 및 서버 관리](#5-관리자-콘솔-및-서버-관리)
6. [점검 결과 수집·조회·내보내기](#6-점검-결과-수집조회내보내기)
7. [대시보드 및 리포트](#7-대시보드-및-리포트)
8. [환경 설정 및 실행](#8-환경-설정-및-실행)
9. [배포 절차](#9-배포-절차)
10. [트러블슈팅 및 FAQ](#10-트러블슈팅-및-faq)
11. [Markdown → PDF 출력 가이드](#11-markdown--pdf-출력-가이드)
12. [향후 로드맵/기술부채/개선 제안](#12-향후-로드맵기술부채개선-제안)
- [부록 A. API 라우트 빠른 참조](#부록-a-api-라우트-빠른-참조)
- [부록 B. 환경 변수·설정 파일 참조](#부록-b-환경-변수설정-파일-참조)
- [부록 C. 주요 파일 경로 목록](#부록-c-주요-파일-경로-목록)

---

## 0. TL;DR (30분 온보딩/운영 치트시트)

### 0.1 이 프로젝트는 무엇인가 (한 줄)

- Ansible로 OS/WAS/DB 점검 → 결과(JSON)를 FastAPI가 수집/저장(DB) → 웹 대시보드/리포트에서 통합 조회/내보내기(JSON/CSV) + 관리자 콘솔(회원/서버/점검항목 관리).

### 0.2 “지금 당장” 알아야 하는 접속/배포 정보

> **중요**: 아래는 실운영 인수인계용으로 IP/포트/경로를 포함합니다.  
> 단, **토큰/비밀번호/개인키 내용은 문서에 절대 적지 않습니다.**

| 구분 | 값(예시) | 설명 |
|---|---|---|
| 사용자 접속(웹/API) | `http://115.85.181.103:8000` | 브라우저가 접근하는 주소 |
| 대시보드 | `http://115.85.181.103:8000/api/dashboard` | 메인 UI (로그인 필요) |
| 관리자 콘솔 | `http://115.85.181.103:8000/api/admin` | Maintainer 이상 |
| 배포 대상(SSH) | `root@27.96.129.114:4433` | 배포·재시작이 수행되는 서버 |
| 배포 경로 | `/opt/ansible-monitoring` | 원격에 sync되는 프로젝트 루트 |
| systemd 유닛 | `ansible-api-server.service` | API 서버 프로세스 관리 |

### 0.3 30분 온보딩 체크리스트 (다음 담당자용)

1) **서비스 살아있는지 확인 (서버 내부)**  

```bash
curl -s http://localhost:8000/api/health
systemctl status ansible-api-server
```

2) **외부 접속 확인 (로컬 PC)**  

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://115.85.181.103:8000/api/health
```

3) **관리자 로그인 준비**  
- `api_server/.env`의 `ADMIN_USERNAME/ADMIN_PASSWORD` 기준으로 최초 관리자 계정이 자동 생성됩니다(없을 때만).  
- `/login` → 로그인 후 `/api/admin` 접근.

4) **(필요 시) DB 스키마 최신화**  
기존 배포본에서 관리자 페이지가 500이면(특히 role 컬럼/서버 테이블), 배포 서버에서:

```bash
cd /opt/ansible-monitoring/api_server
./venv/bin/python3 migrate_add_role.py
systemctl restart ansible-api-server
```

5) **점검 1회 실행 후 대시보드 확인**  
- (정적 인벤토리) `ansible-playbook -i hosts.ini ...`  
- (동적 인벤토리) 아래 0.5 참고.

### 0.4 운영 치트시트 (가장 자주 쓰는 명령)

```bash
# 서비스 상태/재시작/로그
systemctl status ansible-api-server
systemctl restart ansible-api-server
journalctl -u ansible-api-server -n 80 --no-pager

# 헬스체크
curl -s http://localhost:8000/api/health

# SSH 접속(PEM 키 사용)
ssh -p 4433 -i /home/sth0824/.ssh/nimso2026.pem root@27.96.129.114
```

### 0.5 “관리자에서 등록한 서버로” Ansible 점검 실행 (동적 inventory)

이 프로젝트는 **관리자 콘솔에서 등록한 서버 목록을 API에서 동적 inventory로 제공**하며, 이를 통해 `hosts.ini` 없이 점검을 실행할 수 있습니다.

- 동적 inventory API: `GET /api/inventory`  
- 실행 스크립트: `run_checks_from_api.sh` (API 키 기반, Cron/운영용)

```bash
# 예) 배포 서버에서
cd /opt/ansible-monitoring
INVENTORY_API_KEY=... ./run_checks_from_api.sh
```

### 0.6 보안/비밀값 원칙 (문서/레포 공통)

- **절대 저장/공유 금지**: GitHub 토큰(PAT), DB 비밀번호, PEM/개인키 내용, INVENTORY_API_KEY, ENCRYPTION_KEY(또는 ANSIBLE_SERVER_ENCRYPTION_KEY)
- `.env`는 커밋하지 않으며(`.env.example`만 유지), 운영 서버에서는 권한을 제한합니다.

### 0.7 용어/표기(필수)

| 용어 | 의미 | 실제 값/예시 |
|---|---|---|
| check_type | 점검 유형 | `os`, `was`, `tomcat`, `mariadb`, `postgresql`, `cubrid` |
| status | 점검 상태 | `success`, `warning`, `error` |
| results | 점검 상세 결과(JSON) | `{ "cpu": {...}, "memory": {...} }` 등 |
| SERVER_HOST | 배포(SSH) 대상 | `27.96.129.114` |
| ACCESS_HOST | 사용자 접속 주소 | `115.85.181.103` |
| check_enabled | “점검 대상 여부” | `true`면 동적 inventory에 포함 |

## 1. 개요 및 목적

### 1.1 문서 목적

본 문서는 **Ansible 기반 서버 점검 자동화** 프로젝트를 다음 담당자에게 인수인계하기 위한 기술 문서입니다. 인수인계 대상자는 이 문서를 통해 다음을 파악할 수 있어야 합니다.

- **기능 범위**: 어떤 기능이 구현되어 있으며, 어디서 동작하는지
- **코드 구조**: 진입점, 라우트, 인증, DB, 템플릿의 위치와 역할
- **운영·배포**: 로컬 실행 방법, 배포 서버 구조, 배포 스크립트 사용법
- **장애 대응**: 자주 발생하는 오류와 해결 절차

문서에서 언급하는 경로는 **프로젝트 루트**(`ansible/`) 기준 상대 경로이며, 필요 시 `api_server/`, `scripts/` 등 하위 디렉터리를 명시합니다.

### 1.2 프로젝트 한 줄 요약

**Ansible**으로 OS / WAS(Tomcat) / DB(MariaDB, PostgreSQL, CUBRID) 점검을 수행하고, 그 결과를 **FastAPI 기반 API 서버**가 수집하여 **DB에 저장**한 뒤, **웹 대시보드·리포트**(테이블, 차트, 상세 보기, 실시간 반영)로 조회·내보내기할 수 있는 점검 자동화 시스템입니다.

### 1.3 주요 산출물

| 산출물 | 설명 |
|--------|------|
| 웹 대시보드 | 로그인 후 KPI·필터·문제 테이블·차트·실시간 업데이트·점검 결과 내보내기(JSON/CSV) |
| 관리자 콘솔 | 회원 목록·승인/반려/삭제/역할 변경, 서버(점검 대상) CRUD·점검 여부 토글 |
| 점검 결과 수집 API | `POST /api/checks`로 Ansible에서 JSON 전송 → DB 저장, WebSocket으로 대시보드에 알림 |
| Ansible 플레이북·역할 | redhat_check(OS), tomcat_check(WAS), mariadb_check, postgresql_check, cubrid_check(DB), common/roles/api_sender(전송) |

### 1.4 기술 스택

| 구분 | 기술 |
|------|------|
| 자동화 | Ansible 2.9+ |
| 백엔드 | FastAPI (Python 3.8+) |
| DB | SQLite(기본·개발용) / PostgreSQL(권장·운영) |
| 프론트엔드 | HTML/CSS/JavaScript, Chart.js |
| 실시간 | WebSocket (새 점검 결과 시 대시보드 갱신 트리거) |
| 인증 | JWT(쿠키 저장), bcrypt 비밀번호 해시, 역할 기반 접근(admin/maintainer/operator/viewer) |

### 1.5 참고 문서

- **README.md** (프로젝트 루트): 전체 개요, 빠른 시작, 플레이북·설정, 디렉터리 구조
- **TROUBLESHOOTING.md** (프로젝트 루트): 연결 거부, 배포 후 확인, 관리자 500, 서비스 실패 시 조치
- **api_server/README.md**: API 서버 전용 설명
- **api_server/docs/AUTH_STRENGTHEN_PLAN.md**: 인증 강화 계획(비밀번호 정책, rate limit, JWT/HTTPS 등)

---

## 2. 시스템 아키텍처 및 데이터 흐름

### 2.1 전체 파이프라인

점검 결과가 Ansible에서 API 서버를 거쳐 DB에 저장되고, 웹에서 조회·표시되기까지의 흐름은 다음과 같습니다.

```mermaid
sequenceDiagram
  participant Ansible
  participant ApiSender
  participant API
  participant DB
  participant WebSocket
  participant Dashboard

  Ansible->>ApiSender: playbook 실행 후 결과 수집
  ApiSender->>API: POST /api/checks (JSON)
  API->>DB: save_check_result
  API->>WebSocket: broadcast new_check_result
  WebSocket->>Dashboard: 클라이언트 갱신 트리거
  Dashboard->>API: GET /api/checks 등
  API->>DB: get_check_results
  DB-->>API: 결과 목록
  API-->>Dashboard: JSON 응답
```

컴포넌트 관점(“뭐가 어디서 돌아가나”)으로 다시 그리면 아래와 같습니다.

```mermaid
flowchart LR
  subgraph controlPlane [ControlPlane(실행/운영)]
    AdminUI[AdminConsole(/api/admin)]
    DashboardUI[Dashboard(/api/dashboard)]
    Scripts[DeployScripts+RunScripts]
  end

  subgraph automation [Automation(Ansible)]
    Playbooks[Playbooks(redhat/tomcat/db)]
    Sender[common/roles/api_sender]
  end

  subgraph apiServer [API_Server(FastAPI)]
    API[main.py]
    Auth[auth.py(JWT+Roles)]
    DBLayer[database.py+models.py]
    WS[/ws(WebSocket)/]
    Templates[HTMLTemplates]
  end

  subgraph storage [Storage]
    DB[(SQLite_or_PostgreSQL)]
  end

  Scripts -->|rsync+systemctl| API
  Playbooks --> Sender -->|POST /api/checks| API
  API --> DBLayer --> DB
  API --> WS --> DashboardUI
  DashboardUI -->|GET /api/checks| API
  AdminUI -->|CRUD APIs| API
  Templates --> DashboardUI
```

1. **Ansible playbook 실행**: `ansible-playbook -i inventory redhat_check/redhat_check.yml` 등으로 대상 서버에서 점검 수행.
2. **결과 수집·전송**: 공통 역할 `common/roles/api_sender`가 점검 결과를 JSON으로 구성하여 API 서버의 `POST /api/checks`로 전송.
3. **API 서버**: FastAPI가 요청을 받아 `save_check_result()`로 DB에 저장하고, WebSocket에 `new_check_result` 이벤트를 브로드캐스트.
4. **대시보드/리포트**: 브라우저에서 `/api/dashboard` 등으로 접속해 `GET /api/checks`(및 유형별 data API)로 데이터를 조회하고, WebSocket으로 실시간 갱신 여부를 반영.

### 2.2 역할 구분

| 구분 | 내용 |
|------|------|
| **Ansible** | redhat_check(OS), tomcat_check(WAS), mariadb_check, postgresql_check, cubrid_check(DB), common/roles/api_sender(API 전송) |
| **API 서버** | FastAPI 앱(main.py), 인증(auth.py), DB(database.py, models.py), HTML 템플릿(대시보드·리포트·관리자·로그인·회원가입·JSON 뷰어) |
| **배포** | 로컬 PC에서 `deploy_current_branch.sh` 실행 → rsync/ssh로 배포 서버에 파일 전송 → systemd로 ansible-api-server 재시작 |

### 2.3 접속 주소와 배포 주소

배포 스크립트(`deploy_current_branch.sh`)에서는 **배포 대상(SSH)** 과 **사용자 접속 주소** 를 구분해 두고 있습니다.

| 항목 | 변수명 | 예시 값 | 설명 |
|------|--------|---------|------|
| 배포(SSH) 호스트 | SERVER_HOST | 27.96.129.114 | rsync·ssh로 배포가 수행되는 서버 |
| SSH 포트 | SERVER_PORT | 4433 | SSH 접속 시 사용 포트(네이버 클라우드 등에서 22 대신 사용하는 경우) |
| SSH 사용자 | SERVER_USER | root | 배포 서버 로그인 계정 |
| SSH 키 | SSH_KEY | /home/sth0824/.ssh/nimso2026.pem | PEM 키 파일 경로(로컬) |
| 사용자 접속 주소 | ACCESS_HOST | 115.85.181.103 | 브라우저에서 접속하는 URL의 호스트 |
| API 포트 | ACCESS_PORT | 8000 | API·대시보드 서비스 포트 |

SERVER_HOST와 ACCESS_HOST가 다르면(예: 서로 다른 IP), 방화벽·ACG에서 8000 포트 인바운드 허용이 접속 주소 쪽이 아니라 **실제 API가 동작하는 배포 서버**에 필요할 수 있으므로, TROUBLESHOOTING.md의 "연결 거부" 절을 참고하세요.

배포 플로우(“어떻게 서버에 반영되나”)는 다음과 같습니다.

```mermaid
flowchart TD
  LocalRepo[LocalRepo(/home/sth0824/ansible)]
  DeployScript[deploy_current_branch.sh]
  SSH[SSH(root@27.96.129.114:4433)]
  RemoteDir[/opt/ansible-monitoring]
  VenvPip[venv_pip_install(requirements.txt)]
  Systemd[systemctl_restart(ansible-api-server)]
  HealthLocal[curl_localhost:8000/api/health]
  HealthPublic[curl_115.85.181.103:8000/api/health]

  LocalRepo --> DeployScript --> SSH --> RemoteDir
  RemoteDir --> VenvPip --> Systemd
  Systemd --> HealthLocal --> HealthPublic
```

### 2.4 디렉터리 구조

| 경로 | 역할 |
|------|------|
| **api_server/** | FastAPI 애플리케이션, 인증, DB, HTML 템플릿, .env, requirements.txt, migrate_add_role.py |
| **scripts/** | ansible-api-server.service(systemd 유닛), auto_deploy_cron.sh 등 |
| **common/** | Ansible 공통 역할(예: api_sender), README |
| **redhat_check/** | OS 점검 플레이북·역할 |
| **tomcat_check/** | WAS(Tomcat) 점검 플레이북·역할 |
| **mariadb_check/**, **postgresql_check/**, **cubrid_check/** | DB별 점검 플레이북·역할 |
| **config/** | api_config.yml(API URL, 기본 checker 등), 인벤토리 관련 |
| **docs/** | 본 인수인계 문서(HANDOVER.md) 등 |
| **fix_postgresql_sequence.sh** | check_results 등 PostgreSQL 시퀀스 정리(필요 시) |
| **auto_check_navercloud.sh**, **run_navercloud_checks.sh** | 네이버 클라우드 점검 실행 |
| **install_ansible.sh** | Ansible 설치 |
| **setup_server_auto_check.sh** | 서버 자동 점검 설정 |

---

## 3. API 서버 상세

### 3.1 진입점 및 초기화

- **진입점**: `api_server/main.py`
- **앱 생성**: FastAPI 인스턴스, lifespan으로 시작 시 `init_db()`, `ensure_admin_user()` 호출. DB 초기화 실패 시에도 프로세스는 기동하고 `/api/health`에서 DB 상태를 degraded로 반환.
- **CORS**: allow_origins=`["*"]`, allow_credentials=True (프로덕션에서는 특정 도메인으로 제한 권장).
- **WebSocket**: `ConnectionManager`로 연결 목록 관리, 새 점검 결과 수신 시 `broadcast`로 모든 클라이언트에 전달.

### 3.2 라우트 일람

아래 표는 Method, Path, 설명, 인증 요구, 비고를 정리한 것입니다. 인증: Public(비로그인), User(로그인 사용자), Maintainer(Maintainer 이상), Admin(Admin 전용).

| Method | Path | 설명 | 인증 |
|--------|------|------|------|
| GET | / | 로그인 여부에 따라 /login 또는 /api/dashboard로 리다이렉트 | Cookie |
| GET | /login | 로그인 페이지(HTML) | Public |
| GET | /register | 회원가입 페이지(HTML) | Public |
| GET | /api/health | 서버·DB 상태 확인 | Public |
| POST | /api/auth/register | 회원가입(승인 전 로그인 불가) | Public |
| POST | /api/auth/login | 로그인, 쿠키에 JWT 설정 | Public |
| POST | /api/auth/logout | 로그아웃, 쿠키 제거 | Public |
| GET | /api/auth/me | 현재 사용자 정보 | User |
| GET | /api/admin | 관리자 콘솔(HTML) | Maintainer |
| GET | /api/admin/users | 회원 목록 | Maintainer |
| POST | /api/admin/users/{id}/approve | 회원 승인 | Maintainer |
| POST | /api/admin/users/{id}/reject | 회원 거부(승인 해제) | Maintainer |
| DELETE | /api/admin/users/{id} | 회원 삭제 | Admin |
| PATCH | /api/admin/users/{id}/role | 회원 역할 변경 | Admin |
| GET | /api/admin/servers | 서버 목록 | Maintainer |
| POST | /api/admin/servers | 서버 추가 | Maintainer |
| GET | /api/admin/servers/{id} | 서버 조회 | Maintainer |
| PUT | /api/admin/servers/{id} | 서버 수정 | Maintainer |
| DELETE | /api/admin/servers/{id} | 서버 삭제 | Maintainer |
| PATCH | /api/admin/servers/{id}/check-enabled | 점검 여부 토글 | Maintainer |
| POST | /api/admin/servers/bulk-upload | 서버 접속 정보 엑셀 업로드(수정+신규) | Maintainer |
| GET | /api/admin/check-items | 점검 항목 목록(유형별) | Maintainer |
| POST | /api/admin/check-items | 점검 항목 추가 | Maintainer |
| PATCH | /api/admin/check-items/{item_id} | 점검 항목 수정(활성/표시명/정렬) | Maintainer |
| DELETE | /api/admin/check-items/{item_id} | 점검 항목 삭제 | Maintainer |
| GET | /api/inventory | Ansible 동적 inventory(JSON) | Maintainer 또는 API Key |
| POST | /api/checks | 점검 결과 수집(Ansible → API) | Public |
| GET | /api/checks | 점검 결과 목록 조회(필터·limit) | User |
| GET | /api/checks/export | 점검 결과 내보내기(JSON/CSV, 필터·ids) | User |
| GET | /api/dashboard | 대시보드(HTML), 미인증 시 로그인으로 리다이렉트 | User |
| GET | /api/report | 통합 리포트(HTML) | User |
| GET | /api/report-legacy | 기존 통합 리포트(HTML) | User |
| GET | /api/json-viewer | JSON 뷰어(HTML) | User |
| GET | /api/db-checks/report | DB 점검 리포트(HTML) | User |
| GET | /api/db-checks/data | DB 점검 데이터(JSON) | User |
| GET | /api/os-checks/report | OS 점검 리포트(HTML) | User |
| GET | /api/os-checks/data | OS 점검 데이터(JSON) | User |
| GET | /api/was-checks/report | WAS 점검 리포트(HTML) | User |
| GET | /api/was-checks/data | WAS 점검 데이터(JSON) | User |
| WebSocket | /ws | 실시간 알림(새 점검 결과 등) | — |

### 3.3 인증 구조 (auth.py)

- **JWT**: 알고리즘 HS256, 만료 24시간, 시크릿은 환경변수 `JWT_SECRET_KEY`(없으면 코드 내 기본값).
- **쿠키**: 이름 `session`, HttpOnly, SameSite=Lax, 로그인 성공 시 설정.
- **함수**: `create_access_token(user_id, username, role, is_admin)`, `decode_access_token(token)`, `get_token_from_request(request)`.
- **의존성**:
  - `get_current_user`: 쿠키 JWT 검증 후 User 반환, 실패 시 401.
  - `get_current_admin`: role == admin 만 허용.
  - `get_current_maintainer`: admin 또는 maintainer.
  - `get_current_operator`: admin, maintainer, operator.
- **역할 상수**: ROLE_ADMIN, ROLE_MAINTAINER, ROLE_OPERATOR, ROLE_VIEWER. User 모델에 `role` 컬럼이 없을 경우 `is_admin`으로 admin/viewer 구분.

### 3.4 데이터 모델 (models.py)

- **User**: id, username, email, password_hash, is_approved, is_admin, role, created_at. 테이블명 `users`. `to_dict()`에서 비밀번호 제외, role 반환.
- **CheckResult**: id, check_type, hostname, check_time, checker, status, results(JSON), created_at. 테이블명 `check_results`. PostgreSQL 사용 시 시퀀스는 fix_postgresql_sequence.sh로 맞춰 두는 것이 좋음.
- **Server**: id, name, ip, os_type, ssh_port, ssh_user, check_enabled, memo, created_at, updated_at. 테이블명 `servers`.

### 3.5 DB 접근 (database.py)

- **연결**: `DATABASE_URL`(환경변수 또는 .env, 기본값 SQLite `api_server/check_results.db`). PostgreSQL 시 pool_pre_ping, pool_recycle 등 설정.
- **세션**: `SessionLocal`, `init_db()`로 Base.metadata.create_all.
- **사용자**: get_user_by_username, get_user_by_id, create_user, get_all_users, set_user_approved, delete_user, set_user_role.
- **서버**: list_servers, get_server, create_server, update_server, delete_server, set_server_check_enabled.
- **점검 결과**: save_check_result, get_check_results(check_type, hostname, checker, limit, created_after, created_before, ids).
- **초기화**: ensure_admin_user() — .env의 ADMIN_USERNAME/ADMIN_PASSWORD로 최초 관리자 생성(없을 때만). migrate_add_role.py는 기존 DB에 users.role 컬럼 추가 및 is_admin 기반 백필용(1회 실행).

#### database.py 주요 함수 시그니처 요약

| 함수 | 용도 |
|------|------|
| init_db() | Base.metadata.create_all로 테이블 생성 |
| check_db_connection() | (bool, str) 연결 테스트 |
| save_check_result(check_type, hostname, check_time, checker, status, results) | 점검 결과 1건 저장 |
| get_check_results(check_type, hostname, checker, limit, created_after, created_before, ids) | 점검 결과 목록 조회, 최신순·limit |
| get_user_by_username(username), get_user_by_id(user_id) | 사용자 조회 |
| create_user(username, password, email) | 회원가입, role=viewer, is_approved=False |
| get_all_users(), set_user_approved(user_id, approved), delete_user(user_id), set_user_role(user_id, role) | 회원 관리 |
| list_servers(check_enabled), get_server(id), create_server(...), update_server(...), delete_server(id), set_server_check_enabled(id, enabled) | 서버 CRUD·점검 여부 |
| ensure_admin_user() | ADMIN_USERNAME/ADMIN_PASSWORD로 최초 관리자 없으면 생성 |

---

## 4. 회원 및 권한

### 4.1 회원가입·로그인 흐름

1. 사용자가 `/register`에서 회원가입 폼 제출 → `POST /api/auth/register` → `create_user(username, password, email)`. 기본 role=viewer, is_approved=False.
2. 관리자(또는 Maintainer)가 `/api/admin` 회원 관리 탭에서 해당 사용자를 **승인** → `POST /api/admin/users/{id}/approve` → set_user_approved(id, True).
3. 승인된 사용자만 `/login`에서 로그인 가능. `POST /api/auth/login` → 비밀번호 검증, JWT 생성, 쿠키 설정.

### 4.2 역할 체계

| 역할 | 할 수 있는 작업(요약) |
|------|------------------------|
| admin | 회원 목록·승인·반려·삭제·역할 변경, 서버 CRUD·점검 여부, 대시보드·리포트·관리자 콘솔 전체 |
| maintainer | 회원 목록·승인·반려, 서버 CRUD·점검 여부, 대시보드·리포트·관리자 콘솔(삭제·역할 변경 제외) |
| operator | 대시보드·리포트·점검 조회·내보내기 등(관리자 콘솔·회원 관리 불가) |
| viewer | 대시보드·리포트·점검 조회·내보내기 등(읽기 위주) |

관리자 콘솔 접근: Maintainer 이상. 회원 삭제·역할 변경은 Admin 전용. 서버 CRUD는 Maintainer 이상.

### 4.3 마이그레이션 (migrate_add_role.py)

기존 DB에 `users.role` 컬럼이 없는 경우(과거 버전 배포본) 한 번 실행해야 합니다. 배포 서버에서:

```bash
cd /opt/ansible-monitoring/api_server
./venv/bin/python3 migrate_add_role.py
systemctl restart ansible-api-server
```

실행 후 관리자 페이지 500(회원 목록/서버 목록 실패)이 해결됩니다.

---

## 5. 관리자 콘솔 및 서버 관리

### 5.1 URL 및 접근

- **URL**: `/api/admin`. Maintainer 이상만 접근 가능(미권한 시 403).
- **기능**: **서버 관리** 탭(점검 대상 서버 추가/수정/삭제, 점검 여부 토글), **회원 관리** 탭(목록, 승인, 반려, 역할 변경, 삭제(Admin만)).

### 5.2 UI (admin_template.html)

- 탭: **서버 관리** | **회원 관리** | **점검 항목 관리**
- 서버 관리:
  - 테이블(호스트명, IP, OS, SSH 포트/사용자, 점검 여부, 메모)
  - 서버 추가/수정 모달(SSH 인증 방식: key_file/password, 키경로, 비밀번호(비우면 유지))
  - 행별 수정/삭제/점검 여부 토글
  - **엑셀 일괄 업로드**(수정 + 신규 등록): `.xlsx` 업로드로 서버/접속정보를 일괄 반영
- 회원 관리:
  - 테이블(아이디, 이메일, 역할, 승인 상태, 가입일)
  - 승인/거부(=승인 해제) (Maintainer 이상)
  - 역할 변경/삭제 (Admin 전용)
- 점검 항목 관리:
  - 유형별 results 세부 키를 추가/삭제하고 enabled를 토글
  - **변경 즉시 신규 점검(POST /api/checks)에 반영**: 비활성 항목은 저장되지 않음

### 5.3 엑셀 업로드(서버 접속 정보) 상세

- API: `POST /api/admin/servers/bulk-upload` (Maintainer 이상)
- 파일: `.xlsx` (openpyxl 사용)
- **컬럼 순서**: 상관없음(헤더명 기반 매핑)
- **지원 헤더**(한글/영문 혼용 가능):
  - 필수 키(수정/조회용): `name`/`호스트명`, 또는 `ip`
  - 선택(수정 시): `password`/`비밀번호`, `ssh_user`/`SSH사용자` (비우면 기존 유지)
  - 선택(신규 등록 시): `os_type`/`OS유형`, `ssh_port`/`SSH포트`, `memo`/`비고`, `ssh_auth_type`/`인증방식`, `ssh_key_path`/`키경로`
- **동작 규칙**
  - (수정) name 우선 매칭 → 없으면 ip로 매칭 → 있으면 업데이트
  - (신규 등록) 매칭 실패 + name과 ip 둘 다 있으면 신규 서버 생성
  - (실패) name/ip 둘 다 비었거나, 신규 등록 요건(name+ip) 미충족 시 details에 실패 행 정보 반환

### 5.4 점검 항목 관리(CheckItem) 상세

- API: `GET/POST/PATCH/DELETE /api/admin/check-items`
- 모델: `api_server/models.py`의 `CheckItem` (check_type, item_key, display_name, enabled, sort_order)
- 반영 위치: `POST /api/checks` 처리 시 `get_enabled_item_keys_for_type(check_type)` 결과가 있으면 **enabled=true 항목만 results에 저장**합니다.

### 5.3 서버 모델 및 API 대응

| API | DB 함수 |
|-----|---------|
| GET /api/admin/servers | list_servers() |
| POST /api/admin/servers | create_server() |
| GET /api/admin/servers/{id} | get_server() |
| PUT /api/admin/servers/{id} | update_server() |
| DELETE /api/admin/servers/{id} | delete_server() |
| PATCH /api/admin/servers/{id}/check-enabled | set_server_check_enabled() |

서버 필드: name, ip, os_type, ssh_port, ssh_user, check_enabled, memo.

---

## 6. 점검 결과 수집·조회·내보내기

### 6.1 수집 (POST /api/checks)

- **인증**: 없음(Ansible에서 호출하므로).
- **요청 스키마**: check_type, hostname, check_time, checker, status, results(JSON).
- **처리**:
  - (1) **점검 항목 설정 반영**: 관리자에서 CheckItem을 설정한 경우, enabled=true 항목만 results에 남기고 저장합니다(불필요/민감 항목 수집 최소화 목적).
  - (2) `save_check_result()`로 DB 저장
  - (3) WebSocket으로 `new_check_result` 브로드캐스트
  - Ansible 호환을 위해 인증 없이 받도록 유지(운영 상 위험을 줄이려면 IP 제한 또는 API Key 방식으로 강화 가능)

### 6.2 조회 (GET /api/checks)

- **인증**: 로그인 사용자.
- **쿼리**: check_type, hostname, checker, id(단건), limit. 내부적으로 get_check_results(..., created_after, created_before, ids) 사용 가능.

### 6.3 내보내기 (GET /api/checks/export)

- **인증**: 로그인 사용자.
- **쿼리**: format=json(기본)|csv, limit, check_type, hostname, checker, created_after, created_before, ids(쉼표 구분 ID).
- **JSON**: `{"success", "count", "results"}` 형태, Content-Disposition: attachment; filename="check_results.json".
- **CSV**: 컬럼 id, check_type, hostname, check_time, checker, status, created_at, results(results는 JSON 문자열). Content-Disposition: attachment; filename="check_results.csv".
- **대시보드**: "내보내기" 버튼 → 모달에서 현재 필터 기준 목록(최대 500건 표시), 체크박스로 선택·전체 선택, 형식(JSON/CSV), "선택한 항목 내보내기" / "필터 결과 전체 내보내기". 선택한 항목은 ids=1,2,3 형태로 export API에 전달. 필터 전체는 현재 대시보드 필터(기간·유형·호스트·담당자)와 최대 건수로 created_after/created_before 등 쿼리 파라미터 구성 후 호출.
- **JSON 뷰어**: 유형·limit·형식(JSON/CSV) 선택 후 "내보내기" 버튼으로 동일 export API 호출. credentials: 'include'로 쿠키 전송, blob 다운로드.

---

## 7. 대시보드 및 리포트

### 7.1 대시보드 (dashboard_template.html)

- **서빙**: GET /api/dashboard. 미인증 시 로그인 페이지로 리다이렉트.
- **구성**: KPI 카드(전체 점검 건수, 오늘 점검, 정상 서버, 경고/에러 서버), 필터(기간(전체/오늘/7일/30일), 유형(OS/DB/WAS), 호스트명, 담당자, 자동 새로고침), 문제 테이블, 차트, 실시간(WebSocket), 내보내기 모달(선택·필터 전체·JSON/CSV). 필터 상태는 localStorage에 저장되어 유지됨.
- **데이터 로드**: reloadDashboard() → fetchChecks(2000)로 GET /api/checks 호출 후 applyDashboardFilters()로 클라이언트 필터 적용, aggregate()로 KPI·문제 목록·차트 데이터 생성. WebSocket /ws 연결 시 type=new_check_result 메시지 수신하면 자동 새로고침(자동 새로고침 체크 시).

### 7.2 리포트 페이지

- **DB**: /api/db-checks/report(HTML), /api/db-checks/data(JSON). report_template.html.
- **OS**: /api/os-checks/report, /api/os-checks/data. os_report_template.html.
- **WAS**: /api/was-checks/report, /api/was-checks/data. was_report_template.html.
- **통합**: /api/report(대시보드와 동일 또는 유사), /api/report-legacy(기존 통합). unified_report_template.html 등.

### 7.3 JSON 뷰어 (json_viewer.html)

- **서빙**: GET /api/json-viewer.
- **기능**: 점검 유형(전체/DB/OS/WAS)·최대 개수·데이터 형식(포맷된/원본 JSON) 선택, "데이터 불러오기", "복사", "내보내기"(형식 JSON/CSV 선택). 내보내기는 getExportUrl()로 /api/checks/export에 format·limit·check_type 전달 후 blob 다운로드.

### 7.4 로그인·회원가입 템플릿

- login_template.html → /login. 로그인 폼, "회원가입" 링크.
- register_template.html → /register. 회원가입 폼(아이디, 비밀번호, 이메일).

---

## 8. 환경 설정 및 실행

### 8.1 api_server/.env

- **DATABASE_URL**: DB 연결 문자열. 없으면 SQLite `api_server/check_results.db`. PostgreSQL 예: `postgresql://user:password@localhost:5432/dbname`.
- **ADMIN_USERNAME**, **ADMIN_PASSWORD**: 최초 관리자 계정(ensure_admin_user에서 사용). 반드시 설정 후 첫 기동 시 관리자로 로그인해 다른 사용자 승인 권장.
- **JWT_SECRET_KEY**: JWT 서명용. 프로덕션에서는 반드시 변경.

참고: api_server/.env.example에 위 항목 예시가 있음.

### 8.2 로컬 실행

1. **가상환경 및 의존성**
   ```bash
   cd api_server
   python3 -m venv venv
   source venv/bin/activate   # Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```
2. **환경 변수**: `api_server/.env`에 최소 DATABASE_URL(선택), ADMIN_USERNAME, ADMIN_PASSWORD, JWT_SECRET_KEY(권장) 설정. 없으면 SQLite와 코드 내 기본 시크릿 사용.
3. **기동**
   ```bash
   ./start_api_server.sh
   # 또는 직접: venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
   ```
4. **PostgreSQL 사용 시**: 프로젝트 루트에서 start_db_server.sh로 DB 기동, stop_db_server.sh로 중지. DATABASE_URL을 postgresql://... 로 맞춘 뒤 API 서버 실행.

### 8.3 배포 서버 구조

- **경로**: /opt/ansible-monitoring (REMOTE_DIR). 그 아래 api_server/, redhat_check/, mariadb_check/, postgresql_check/, tomcat_check/, common/, config/, logs/ 등. deploy 스크립트가 rsync로 동기화.
- **systemd**: scripts/ansible-api-server.service.
  - WorkingDirectory=/opt/ansible-monitoring/api_server
  - ExecStart=/opt/ansible-monitoring/api_server/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
  - Restart=always, RestartSec=5
  - 0.0.0.0으로 바인딩해 외부 접속 수신. 배포 시 /etc/systemd/system/에 복사 후 daemon-reload, enable, start/restart.

---

## 9. 배포 절차

### 9.1 스크립트 (deploy_current_branch.sh)

- **변수**: SERVER_HOST, SERVER_PORT, SERVER_USER, SSH_KEY, REMOTE_DIR, ACCESS_HOST, ACCESS_PORT(위 2.3 참조). 수정 시 스크립트 상단에서 변경.
- **실행**: 프로젝트 루트에서 `./deploy_current_branch.sh`. set -e 이므로 단계 실패 시 중단.
- **순서**:
  1. SSH 접속 테스트: `ssh -i "$SSH_KEY" -p "$SERVER_PORT" ... "echo 'SSH 연결 성공'"`. 실패 시 "핫스팟 연결 확인" 등 안내 후 종료.
  2. API 서버 파일 업로드: rsync로 ./api_server/ → $REMOTE_DIR/api_server/. venv, __pycache__, .git, check_results.db, *.log 제외.
  3. API 서버 의존성 설치: 원격에서 `cd $REMOTE_DIR/api_server && (venv 있으면 pip install -r requirements.txt, 없으면 venv 생성 후 설치)`.
  4. Ansible 파일 업로드: redhat_check, mariadb_check, postgresql_check, tomcat_check, common, config, hosts.ini.server, ansible.cfg, auto_check_navercloud.sh, install_ansible.sh, scripts/ansible-api-server.service 등 rsync/scp. SSH 키도 원격 .ssh/에 복사.
  5. Ansible 설치 확인: 원격에서 ansible-playbook 없으면 install_ansible.sh 실행.
  6. systemd: ansible-api-server.service를 /etc/systemd/system/에 복사, daemon-reload, enable, restart. sleep 3 후 status 출력.
  7. 배포 확인: sleep 5 후 localhost:8000/api/health, ACCESS_HOST:8000/api/health 각각 curl로 HTTP 코드 확인. 200이면 성공, 아니면 실패/방화벽 안내.

### 9.2 최초 배포 시

- 서버에 scripts/ansible-api-server.service 복사 후 `cp ... /etc/systemd/system/`, `systemctl daemon-reload`, `systemctl enable ansible-api-server`, `systemctl start ansible-api-server`.
- DB가 이미 있는 경우(기존 users 테이블에 role 없음): `cd /opt/ansible-monitoring/api_server && ./venv/bin/python3 migrate_add_role.py` 실행 후 `systemctl restart ansible-api-server`.

### 9.3 PEM 키·계정

- SSH 접속 예: `ssh -p 4433 -i /path/to/nimso2026.pem root@27.96.129.114`. 비밀번호 입력란에는 PEM 키 내용을 넣지 말고, `-i`로 키 파일을 지정해 접속합니다. 키 파일 권한(600) 및 보안 유지.

---

## 10. 트러블슈팅 및 FAQ

### 10.1 연결 거부

- **증상**: 브라우저에서 접속 주소(예: 115.85.181.103:8000) 연결 거부.
- **확인**: SERVER_HOST와 ACCESS_HOST가 같은 서버인지, 다른 서버인지 구분. 같은 서버면 방화벽/ACG에서 TCP 8000 인바운드 허용. API 서버 기동 여부: `systemctl status ansible-api-server`, `curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/api/health` → 200 기대.
- 자세한 단계: TROUBLESHOOTING.md "연결 거부" 절.

### 10.2 관리자 페이지 500

- **증상**: /api/admin 접속 시 500 또는 회원/서버 목록 실패.
- **원인**: users.role 컬럼 없음 또는 servers 테이블 없음(스키마 미반영).
- **조치**: migrate_add_role.py 실행, systemctl restart ansible-api-server. TROUBLESHOOTING.md "관리자 페이지에서 500" 절.

### 10.3 배포 후 HTTP 000

- **증상**: 배포 스크립트 마지막 확인에서 localhost 또는 ACCESS_HOST 응답이 000.
- **조치**: 스크립트에서 health 확인 전 sleep 5초 적용됨. 서버에서 직접 `curl -s http://localhost:8000/api/health` 확인. 실패 시 `journalctl -u ansible-api-server -n 50 --no-pager`로 오류 확인.

### 10.4 DB 연결 실패

- **증상**: API 기동 실패 또는 /api/health에서 db: error.
- **조치**: DATABASE_URL 확인, PostgreSQL 사용 시 해당 서버에서 PostgreSQL 기동, psql로 접속 테스트. 필요 시 fix_postgresql_sequence.sh로 check_results 시퀀스 정리.

### 10.5 자주 쓰는 명령

```bash
systemctl status ansible-api-server
systemctl restart ansible-api-server
journalctl -u ansible-api-server -n 80 --no-pager
curl -s http://localhost:8000/api/health
```

### 10.6 FAQ

- **Q: 회원가입은 어디서 하나요?**  
  A: `/register` 또는 로그인 페이지의 "회원가입" 링크. 가입 후 관리자 승인 전까지는 로그인 불가.

- **Q: 점검 결과가 안 올라와요.**  
  A: config/api_config.yml의 api_server.url(또는 urls)이 실제 API 서버 주소와 /api/checks 경로를 포함하는지 확인. Ansible playbook 실행 후 해당 URL로 POST가 나가는지 네트워크/로그 확인.

- **Q: 대시보드 주소로 들어가면 빈 화면이에요.**  
  A: 미인증이면 로그인 페이지로 리다이렉트됨. 로그인 후에도 빈 화면이면 브라우저 콘솔 오류·네트워크 탭 확인, /api/health·/api/checks 응답 확인.

- **Q: SSH 접속 시 password: 가 나와요. PEM 키를 어디에 넣나요?**  
  A: PEM 키는 비밀번호란에 넣지 않습니다. `ssh -p 4433 -i /경로/파일.pem root@SERVER_HOST` 처럼 `-i` 옵션으로 키 파일 경로를 지정해 접속합니다.

- **Q: 배포 후 확인에서 HTTP 000만 나와요.**  
  A: 재시작 직후라 서버가 아직 준비 안 됐을 수 있음. 배포 스크립트는 5초 대기 후 확인. 서버에 SSH 접속해 `curl -s http://localhost:8000/api/health` 로 직접 확인하고, 실패 시 journalctl로 오류 로그 확인.

---

## 부록 A. API 라우트 빠른 참조

| Method | Path | 인증 | 요약 |
|--------|------|------|------|
| GET | / | Cookie | /login 또는 /api/dashboard 리다이렉트 |
| GET | /login | Public | 로그인 페이지 |
| GET | /register | Public | 회원가입 페이지 |
| GET | /api/health | Public | 상태·DB 확인 |
| POST | /api/auth/register | Public | 회원가입 |
| POST | /api/auth/login | Public | 로그인 |
| POST | /api/auth/logout | Public | 로그아웃 |
| GET | /api/auth/me | User | 현재 사용자 |
| GET | /api/admin | Maintainer | 관리자 콘솔 HTML |
| GET/POST | /api/admin/users, .../approve, .../reject | Maintainer | 회원 목록·승인·반려 |
| DELETE | /api/admin/users/{id} | Admin | 회원 삭제 |
| PATCH | /api/admin/users/{id}/role | Admin | 역할 변경 |
| GET/POST/GET/PUT/DELETE/PATCH | /api/admin/servers, .../{id}, .../check-enabled | Maintainer | 서버 CRUD·점검 여부 |
| POST | /api/admin/servers/bulk-upload | Maintainer | 엑셀 업로드(수정+신규 등록) |
| GET/POST/PATCH/DELETE | /api/admin/check-items, .../{id} | Maintainer | 점검 항목 관리 |
| GET | /api/inventory | Maintainer 또는 API Key | Ansible 동적 inventory(JSON) |
| POST | /api/checks | Public | 점검 결과 수집 |
| GET | /api/checks | User | 점검 결과 목록 |
| GET | /api/checks/export | User | 점검 결과 내보내기(JSON/CSV) |
| GET | /api/dashboard, /api/report, /api/report-legacy, /api/json-viewer | User | 대시보드·리포트·JSON 뷰어 |
| GET | /api/db-checks/report, /api/db-checks/data | User | DB 리포트·데이터 |
| GET | /api/os-checks/report, /api/os-checks/data | User | OS 리포트·데이터 |
| GET | /api/was-checks/report, /api/was-checks/data | User | WAS 리포트·데이터 |
| WebSocket | /ws | — | 실시간 알림 |

---

## 부록 B. 환경 변수·설정 파일 참조

| 항목 | 파일/위치 | 설명 |
|------|-----------|------|
| DATABASE_URL | api_server/.env | DB 연결 문자열. 없으면 sqlite:///api_server/check_results.db. PostgreSQL: postgresql://user:password@host:5432/dbname |
| ADMIN_USERNAME | api_server/.env | 최초 관리자 아이디. ensure_admin_user()에서 사용 |
| ADMIN_PASSWORD | api_server/.env | 최초 관리자 비밀번호. 해시 후 저장 |
| JWT_SECRET_KEY | api_server/.env | JWT 서명 시크릿. 프로덕션에서 반드시 변경. 없으면 코드 내 기본값 사용 |
| ENCRYPTION_KEY / ANSIBLE_SERVER_ENCRYPTION_KEY | api_server/.env (권장) 또는 환경변수 | 서버 SSH 비밀번호를 암호화 저장할 때 사용(Fernet). 키가 없으면 비밀번호 저장/복호화 기능이 제한됩니다. |
| INVENTORY_API_KEY | api_server/.env (권장) 또는 환경변수 | `GET /api/inventory`를 API Key로 호출할 때 사용(Cron/스크립트용). 절대 노출 금지. |
| api_server.url / api_server.urls | config/api_config.yml | Ansible common/roles/api_sender가 점검 결과를 보낼 API 기본 URL(예: http://호스트:8000/api/checks 포함) |

**.env.example** (api_server/) 예시:
- DATABASE_URL(주석), ADMIN_USERNAME=admin, ADMIN_PASSWORD=changeme, JWT_SECRET_KEY(주석).

---

## 부록 C. 주요 파일 경로 목록

| 경로 | 설명 |
|------|------|
| deploy_current_branch.sh | 현재 브랜치 배포 스크립트 |
| start_api_server.sh, stop_api_server.sh | API 서버 기동·중지 |
| start_db_server.sh, stop_db_server.sh, restart_db_server.sh | DB 서버(PostgreSQL 등) |
| TROUBLESHOOTING.md | 트러블슈팅 |
| README.md | 프로젝트 개요 |
| scripts/ansible-api-server.service | systemd 유닛 |
| api_server/main.py | FastAPI 앱·라우트 |
| api_server/auth.py | JWT·역할 의존성 |
| api_server/database.py | DB 연결·CRUD |
| api_server/models.py | User, CheckResult, Server 모델 |
| api_server/migrate_add_role.py | users.role 마이그레이션 |
| api_server/.env, .env.example | 환경 변수 |
| api_server/dashboard_template.html | 대시보드 |
| api_server/admin_template.html | 관리자 콘솔 |
| api_server/login_template.html, register_template.html | 로그인·회원가입 |
| api_server/report_template.html, os_report_template.html, was_report_template.html | DB/OS/WAS 리포트 |
| api_server/json_viewer.html | JSON 뷰어 |
| api_server/requirements.txt | Python 의존성 |

---

## 11. Markdown → PDF 출력 가이드

### 11.1 가장 쉬운 방법(권장): VSCode에서 미리보기 → 인쇄(PDF)

1. VSCode에서 `docs/HANDOVER.md` 열기  
2. 우측 상단 **미리보기(Preview)** 열기(또는 `Ctrl+Shift+V`)  
3. 미리보기 창에서 **브라우저 인쇄**(또는 `Ctrl+P`) → **대상: PDF로 저장**  
4. 여백/배경 그래픽/머리글·바닥글 옵션을 조정해 저장

> Mermaid 다이어그램은 VSCode 미리보기 환경에 따라 렌더링이 다를 수 있습니다. 미리보기에서 다이어그램이 깨지면 11.2 방법을 사용하세요.

### 11.2 CLI로 PDF 만들기(선택)

운영 환경에 따라 아래 중 하나를 선택합니다.

- **방법 A: `md-to-pdf` (Node.js)**  
  - 장점: 설치/사용이 단순, CSS 커스터마이즈 쉬움  
  - 단점: Mermaid 렌더는 추가 설정이 필요할 수 있음

```bash
npm i -g md-to-pdf
md-to-pdf /home/sth0824/ansible/docs/HANDOVER.md
```

- **방법 B: `pandoc` + LaTeX 엔진**  
  - 장점: 품질 좋은 PDF, 목차/스타일 제어 용이  
  - 단점: LaTeX 설치 필요

```bash
sudo apt-get update
sudo apt-get install -y pandoc texlive-xetex
pandoc /home/sth0824/ansible/docs/HANDOVER.md -o /home/sth0824/ansible/docs/HANDOVER.pdf --pdf-engine=xelatex
```

### 11.3 PDF 품질 팁(판교 스타일)

- 코드 블록은 너무 길면 “핵심만” 남기고 나머지는 파일 경로로 참조
- 표는 페이지 너비를 넘지 않게 컬럼 수를 조정(특히 API 표)
- 운영 IP/포트/경로는 포함하되, 비밀값은 항상 마스킹(예: `INVENTORY_API_KEY=***`)

## 12. 향후 로드맵/기술부채/개선 제안

### 12.1 보안(우선순위 높음)

- **HTTPS/TLS**: 운영 환경에서 반드시 TLS 종단을 두기(리버스 프록시: Nginx/Caddy/LB). 쿠키 기반 JWT를 쓰므로 HTTPS 없이는 세션 탈취 리스크가 큼.
- **CORS 제한**: 현재 `allow_origins=["*"]` + `allow_credentials=True` 조합은 운영에 부적절. 프론트 도메인을 명시하고 credentials를 유지하거나, 내부망 전용이면 origins를 제한.
- **POST /api/checks 보호**: 현재 Ansible 호환을 위해 Public. 운영에서는
  - (A) API Key 헤더(예: `X-API-Key`) 추가, 또는
  - (B) 배포 서버/Ansible 실행 서버 IP allowlist,
  - (C) 별도 내부망 엔드포인트 분리
  중 하나는 적용 권장.
- **로그인/회원가입 강화**: `api_server/docs/AUTH_STRENGTHEN_PLAN.md`의 1단계(입력검증/비번확인/토글) → 2단계(rate limit) 순으로 적용.

### 12.2 운영 안정성

- **로그 정책**: systemd/journalctl만으로는 운영 추적이 어려우면 `uvicorn` 로그 파일 + logrotate 적용.
- **헬스체크/모니터링**: `/api/health`를 외부 모니터링(업타임 체크)에 연동하고, DB degraded 알람을 분리.
- **DB 마이그레이션 체계화**: 지금은 스크립트 기반(migrate_add_role.py 등). Alembic 도입을 검토하면 운영 DB 변경이 안전해짐.

### 12.3 제품 기능(관리자/데이터)

- **점검 항목 관리 고도화**: 현재는 `results` 키 필터링(저장 시). 향후에는
  - 점검 항목별 임계치(예: CPU>80 warning),
  - 항목별 가시성(대시보드/리포트 노출 여부),
  - 버전 관리(적용 시점)
  를 설계할 수 있음.
- **대시보드 집계 기준 통일**: “누적” vs “최근 점검” 기준을 UI/문구에서 명확히 분리(최근 점검 기준 성공률 등).
- **내보내기(Export) 확장**: CSV flatten, 다중 시트, 대용량 스트리밍, 서버측 필터링 강화.

### 12.4 CI/CD (선택)

- GitHub Actions의 workflow(`.github/workflows/*.yml`)는 **자동 배포**에 유용하지만, 토큰 권한/보안 정책에 따라 운영이 까다로울 수 있음.
- 현 운영은 `deploy_current_branch.sh` 중심(SSH+rsync+systemd). 자동화가 필요하면
  - (A) Actions + 최소 권한 + 배포 전용 키/서버 계정,
  - (B) 배포 서버에서 cron으로 git pull,
  - (C) 내부 CI 서버
  중 하나로 체계화 권장.

*문서 끝.*
