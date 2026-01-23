# 배포 요약

## 배포 방식

### 기존 서버 활용
- **서버**: `nimbus-server` (이미 존재하던 네이버 클라우드 서버)
- **IP**: 115.85.181.103 (실제 공인 IP)
- **OS**: CentOS 7.8
- **사양**: 2vCPU, 4GB RAM, 150GB 스토리지

### 배포 내용

1. **프로젝트 파일 업로드**
   - 로컬 `dev_hwan` 브랜치의 `api_server/` 디렉토리
   - 서버 경로: `/opt/ansible-monitoring/api_server/`

2. **서버에 설치**
   - Python 3.9.18 설치
   - PostgreSQL 설치 및 설정
   - Python 패키지 설치
   - systemd 서비스 등록

3. **로컬 DB 데이터 마이그레이션**
   - 로컬 PostgreSQL (108건) → 서버 PostgreSQL
   - 데이터 덤프 및 복원

## 서버 구조

```
nimbus-server (네이버 클라우드)
├── /opt/ansible-monitoring/
│   ├── api_server/          (프로젝트 파일)
│   │   ├── main.py
│   │   ├── database.py
│   │   ├── models.py
│   │   ├── *.html (템플릿)
│   │   └── venv/ (Python 가상환경)
│   └── logs/
├── PostgreSQL (서버에 설치)
│   └── ansible_checks DB (108건 데이터)
└── systemd 서비스
    └── ansible-api-server.service
```

## 접속 정보

- **API 서버**: http://115.85.181.103:8000
- **대시보드**: http://115.85.181.103:8000/api/dashboard
- **SSH 접속**: `ssh -i ~/.ssh/nimso2026.pem -p 1025 root@27.96.129.114`

## 요약

✅ **기존 서버 활용** (새 서버 생성 안 함)
✅ **로컬 프로젝트 파일 업로드**
✅ **로컬 DB 데이터 마이그레이션**
✅ **서버에 환경 구축** (Python, PostgreSQL)
