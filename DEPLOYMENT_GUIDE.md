# nimbus-server 배포 가이드

## 개요

기존 `nimbus-server`에 API 서버와 PostgreSQL DB 서버를 배포하여 외부에서 접근 가능하게 만드는 가이드입니다.

---

## 사전 준비

### 1. 로컬 환경 확인
- SSH 키 파일: `/home/sth0824/.ssh/nimso2026.pem`
- 서버 접속 가능 여부 확인

### 2. 서버 정보
- **호스트**: `27.96.129.114`
- **포트**: `1025` (SSH 포트 포워딩)
- **사용자**: `root`
- **OS**: CentOS 7.8

---

## 배포 단계

### 1단계: 배포 스크립트 실행

```bash
cd /home/sth0824/ansible
chmod +x deploy_to_nimbus.sh
./deploy_to_nimbus.sh
```

이 스크립트는 다음을 수행합니다:
1. SSH 접속 테스트
2. 서버 디렉토리 생성
3. 프로젝트 파일 업로드
4. 설치 스크립트 업로드
5. 서버에서 자동 설치 실행
6. 서비스 시작

**예상 소요 시간**: 10-15분 (Python 컴파일 포함)

---

### 2단계: ACG (방화벽) 설정

네이버 클라우드 콘솔에서:

1. **Server > nimbus-server > ACG 규칙 보기**
2. **인바운드 규칙 추가**:
   - **포트**: `8000`
   - **프로토콜**: `TCP`
   - **소스**: `0.0.0.0/0` (전체 허용) 또는 특정 IP
   - **설명**: `API Server`

3. **저장**

---

### 3단계: 접속 테스트

배포 완료 후:

```bash
# API 서버 상태 확인
curl http://27.96.129.114:8000/api/health

# 대시보드 접속
# 브라우저에서: http://27.96.129.114:8000/api/dashboard
```

---

## 서비스 관리

### 서비스 상태 확인

```bash
ssh -i ~/.ssh/nimso2026.pem -p 1025 root@27.96.129.114

# API 서버 상태
systemctl status ansible-api-server

# PostgreSQL 상태
systemctl status postgresql
```

### 서비스 제어

```bash
# API 서버 시작/중지/재시작
systemctl start ansible-api-server
systemctl stop ansible-api-server
systemctl restart ansible-api-server

# PostgreSQL 시작/중지/재시작
systemctl start postgresql
systemctl stop postgresql
systemctl restart postgresql
```

### 로그 확인

```bash
# API 서버 로그
journalctl -u ansible-api-server -f

# PostgreSQL 로그
tail -f /var/lib/pgsql/data/pg_log/postgresql-*.log
```

---

## 문제 해결

### 1. SSH 접속 실패

```bash
# 키 파일 권한 확인
chmod 600 ~/.ssh/nimso2026.pem

# 접속 테스트
ssh -i ~/.ssh/nimso2026.pem -p 1025 root@27.96.129.114
```

### 2. API 서버가 시작되지 않음

```bash
# 서비스 상태 확인
systemctl status ansible-api-server

# 로그 확인
journalctl -u ansible-api-server -n 50

# 수동 실행 (디버깅)
cd /opt/ansible-monitoring/api_server
source venv/bin/activate
python3 main.py
```

### 3. PostgreSQL 연결 실패

```bash
# PostgreSQL 상태 확인
systemctl status postgresql

# 데이터베이스 연결 테스트
sudo -u postgres psql -d ansible_checks -c "SELECT 1;"

# 사용자 확인
sudo -u postgres psql -c "\du"
```

### 4. 포트 8000 접속 불가

- ACG 규칙 확인 (포트 8000 허용)
- 서버 방화벽 확인:
  ```bash
  firewall-cmd --list-ports
  firewall-cmd --add-port=8000/tcp --permanent
  firewall-cmd --reload
  ```

---

## 데이터베이스 정보

### 접속 정보
- **호스트**: `localhost` (서버 내부)
- **포트**: `5432`
- **데이터베이스**: `ansible_checks`
- **사용자**: `ansible_user`
- **비밀번호**: `ansible_password_2024`

### 비밀번호 변경 (선택)

```bash
sudo -u postgres psql << 'EOF'
ALTER USER ansible_user WITH PASSWORD '새_비밀번호';
EOF

# .env 파일도 수정
vi /opt/ansible-monitoring/api_server/.env
# DATABASE_URL=postgresql://ansible_user:새_비밀번호@localhost:5432/ansible_checks
```

---

## 파일 위치

### 서버 내 파일 구조

```
/opt/ansible-monitoring/
├── api_server/
│   ├── main.py
│   ├── database.py
│   ├── models.py
│   ├── requirements.txt
│   ├── .env
│   ├── venv/
│   └── ...
├── logs/
└── deploy_install.sh
```

### 서비스 파일

- API 서버: `/etc/systemd/system/ansible-api-server.service`
- PostgreSQL: `/etc/systemd/system/postgresql.service` (기본)

---

## 업데이트 방법

### 코드 업데이트

```bash
# 로컬에서
cd /home/sth0824/ansible
./deploy_to_nimbus.sh

# 또는 수동 업데이트
rsync -avz -e "ssh -i ~/.ssh/nimso2026.pem -p 1025" \
    --exclude='venv' \
    --exclude='__pycache__' \
    ./api_server/ root@27.96.129.114:/opt/ansible-monitoring/api_server/

# 서버에서 재시작
ssh -i ~/.ssh/nimso2026.pem -p 1025 root@27.96.129.114 \
    "systemctl restart ansible-api-server"
```

---

## 보안 권장사항

1. **비밀번호 변경**: 기본 비밀번호를 강력한 비밀번호로 변경
2. **ACG 설정**: 포트 8000은 필요한 IP만 허용
3. **SSH 키 관리**: 키 파일 권한 유지 (`chmod 600`)
4. **정기 업데이트**: 시스템 및 패키지 정기 업데이트
5. **로그 모니터링**: 비정상 접근 로그 확인

---

## 완료 확인

배포가 성공적으로 완료되면:

- ✅ API 서버: http://27.96.129.114:8000 접속 가능
- ✅ 대시보드: http://27.96.129.114:8000/api/dashboard 접속 가능
- ✅ API 문서: http://27.96.129.114:8000/docs 접속 가능
- ✅ 서비스 자동 시작: 서버 재부팅 시 자동 시작

---

## 다음 단계

1. **Ansible 설정 업데이트**: `config/api_config.yml`에서 API 서버 URL 변경
2. **점검 테스트**: Ansible 점검 실행하여 데이터 수집 확인
3. **모니터링 설정**: 서버 리소스 모니터링 설정 (선택)
