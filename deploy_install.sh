#!/bin/bash
# nimbus-server에서 실행할 설치 스크립트

set -e

INSTALL_DIR="/opt/ansible-monitoring"
API_DIR="$INSTALL_DIR/api_server"

echo "=========================================="
echo "nimbus-server 설치 시작"
echo "=========================================="
echo ""

# 1. 시스템 업데이트
echo "[1/8] 시스템 업데이트..."
yum update -y > /dev/null 2>&1
echo "✅ 완료"
echo ""

# 2. Python 3.8+ 설치 (CentOS 7.8은 기본 Python 3.6)
echo "[2/8] Python 3.8+ 설치..."
if ! command -v python3.8 &> /dev/null; then
    yum install -y gcc openssl-devel bzip2-devel libffi-devel zlib-devel > /dev/null 2>&1
    cd /tmp
    if [ ! -f "Python-3.9.18.tgz" ]; then
        wget https://www.python.org/ftp/python/3.9.18/Python-3.9.18.tgz > /dev/null 2>&1
    fi
    if [ ! -d "Python-3.9.18" ]; then
        tar xzf Python-3.9.18.tgz
    fi
    cd Python-3.9.18
    ./configure --enable-optimizations > /dev/null 2>&1
    make altinstall > /dev/null 2>&1
    ln -sf /usr/local/bin/python3.9 /usr/local/bin/python3
    ln -sf /usr/local/bin/pip3.9 /usr/local/bin/pip3
fi
echo "✅ Python 설치 완료: $(python3 --version 2>&1)"
echo ""

# 3. PostgreSQL 설치
echo "[3/8] PostgreSQL 설치..."
if ! command -v psql &> /dev/null; then
    yum install -y postgresql-server postgresql-contrib > /dev/null 2>&1
    
    # PostgreSQL 초기화 (처음 한 번만)
    if [ ! -d "/var/lib/pgsql/data" ] || [ -z "$(ls -A /var/lib/pgsql/data)" ]; then
        postgresql-setup initdb > /dev/null 2>&1
    fi
    
    # PostgreSQL 설정
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost'/" /var/lib/pgsql/data/postgresql.conf
    
    # 인증 설정 (로컬 접근 허용)
    if ! grep -q "ansible_checks" /var/lib/pgsql/data/pg_hba.conf; then
        echo "host    ansible_checks    ansible_user    127.0.0.1/32    md5" >> /var/lib/pgsql/data/pg_hba.conf
        echo "host    ansible_checks    ansible_user    ::1/128         md5" >> /var/lib/pgsql/data/pg_hba.conf
    fi
    
    systemctl enable postgresql
    systemctl start postgresql
    
    # 데이터베이스 및 사용자 생성
    sleep 2
    sudo -u postgres psql << 'PSQL_EOF'
        CREATE DATABASE ansible_checks;
        CREATE USER ansible_user WITH PASSWORD 'ansible_password_2024';
        GRANT ALL PRIVILEGES ON DATABASE ansible_checks TO ansible_user;
        \c ansible_checks
        GRANT ALL ON SCHEMA public TO ansible_user;
PSQL_EOF
fi
echo "✅ PostgreSQL 설치 완료"
echo ""

# 4. Python 가상환경 생성
echo "[4/8] Python 가상환경 생성..."
cd "$API_DIR"
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
echo "✅ 가상환경 생성 완료"
echo ""

# 5. 의존성 설치
echo "[5/8] Python 패키지 설치..."
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt > /dev/null 2>&1
echo "✅ 패키지 설치 완료"
echo ""

# 6. 환경 변수 설정
echo "[6/8] 환경 변수 설정..."
if [ ! -f "$API_DIR/.env" ]; then
    cat > "$API_DIR/.env" << 'ENV_EOF'
# API 서버 설정
API_HOST=0.0.0.0
API_PORT=8000

# PostgreSQL 데이터베이스 설정
DATABASE_URL=postgresql://ansible_user:ansible_password_2024@localhost:5432/ansible_checks

# 로깅
LOG_LEVEL=INFO
ENV_EOF
    chmod 600 "$API_DIR/.env"
fi
echo "✅ 환경 변수 설정 완료"
echo ""

# 7. systemd 서비스 파일 설치
echo "[7/8] systemd 서비스 설치..."
if [ -f "/tmp/ansible-api-server.service" ]; then
    cp /tmp/ansible-api-server.service /etc/systemd/system/
    systemctl daemon-reload
fi
echo "✅ 서비스 파일 설치 완료"
echo ""

# 8. 로그 디렉토리 권한 설정
echo "[8/8] 로그 디렉토리 설정..."
mkdir -p "$INSTALL_DIR/logs"
chmod 755 "$INSTALL_DIR/logs"
echo "✅ 완료"
echo ""

echo "=========================================="
echo "설치 완료!"
echo "=========================================="
echo ""
echo "다음 명령으로 서비스 시작:"
echo "  systemctl start ansible-api-server"
echo "  systemctl status ansible-api-server"
echo ""
