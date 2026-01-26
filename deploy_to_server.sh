#!/bin/bash
# 네이버 클라우드 서버에 배포하는 스크립트

set -e

# 서버 정보
SERVER_HOST="27.96.129.114"
SERVER_PORT="4433"
SERVER_USER="root"
SSH_KEY="/home/sth0824/.ssh/nimso2026.pem"
REMOTE_DIR="/opt/ansible-monitoring"
API_PORT="${1:-8000}"  # 첫 번째 인자로 포트 지정 (기본값: 8000)

# 색상 출력
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current)
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}네이버 클라우드 서버 배포 (포트 ${API_PORT})${NC}"
echo -e "${GREEN}현재 브랜치: ${CURRENT_BRANCH}${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 1. SSH 접속 테스트
echo -e "${YELLOW}[1/5] SSH 접속 테스트...${NC}"
if ssh -i "$SSH_KEY" -p "$SERVER_PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_HOST" "echo 'SSH 연결 성공'" 2>&1 | grep -q "SSH 연결 성공"; then
    echo -e "${GREEN}✅ SSH 접속 성공${NC}"
else
    echo -e "${YELLOW}⚠️  SSH 접속 테스트 실패, 계속 진행...${NC}"
fi
echo ""

# 2. 서버에 디렉토리 생성
echo -e "${YELLOW}[2/5] 서버 디렉토리 생성...${NC}"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << EOF
    mkdir -p ${REMOTE_DIR}/api_server
    mkdir -p ${REMOTE_DIR}/logs
    echo "✅ 디렉토리 생성 완료"
EOF
echo ""

# 3. 프로젝트 파일 업로드
echo -e "${YELLOW}[3/5] 프로젝트 파일 업로드...${NC}"
rsync -avz -e "ssh -i $SSH_KEY -p $SERVER_PORT" \
    --exclude='venv' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.git' \
    --exclude='check_results.db' \
    --exclude='*.log' \
    ./api_server/ "$SERVER_USER@$SERVER_HOST:${REMOTE_DIR}/api_server/"

echo -e "${GREEN}✅ 파일 업로드 완료${NC}"
echo ""

# 4. .env 파일 수정 (포트 설정)
echo -e "${YELLOW}[4/5] 환경 설정 (포트 ${API_PORT})...${NC}"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << EOF
    cat > ${REMOTE_DIR}/api_server/.env << ENV_EOF
# API 서버 설정
API_HOST=0.0.0.0
API_PORT=${API_PORT}

# PostgreSQL 데이터베이스 설정
DATABASE_URL=postgresql://ansible_user:ansible_password_2024@localhost:5432/ansible_checks

# 로깅
LOG_LEVEL=INFO
ENV_EOF
    chmod 600 ${REMOTE_DIR}/api_server/.env
    echo "✅ 환경 설정 완료"
EOF
echo ""

# 5. systemd 서비스 파일 생성 및 등록
echo -e "${YELLOW}[5/5] 서비스 설정 및 시작...${NC}"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << EOF
    # systemd 서비스 파일 생성
    cat > /etc/systemd/system/ansible-api-server.service << SERVICE_EOF
[Unit]
Description=Ansible Monitoring API Server (Port ${API_PORT})
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${REMOTE_DIR}/api_server
Environment="PATH=${REMOTE_DIR}/api_server/venv/bin"
ExecStart=${REMOTE_DIR}/api_server/venv/bin/python3 ${REMOTE_DIR}/api_server/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ansible-api-server

# 환경 변수 로드
EnvironmentFile=${REMOTE_DIR}/api_server/.env

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    # Python 가상환경 생성 (없는 경우)
    if [ ! -d "${REMOTE_DIR}/api_server/venv" ]; then
        cd ${REMOTE_DIR}/api_server
        python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip > /dev/null 2>&1
        pip install -r requirements.txt > /dev/null 2>&1
        echo "✅ 가상환경 생성 및 패키지 설치 완료"
    else
        # 가상환경이 있으면 패키지만 업데이트
        cd ${REMOTE_DIR}/api_server
        source venv/bin/activate
        pip install --upgrade pip > /dev/null 2>&1
        pip install -r requirements.txt > /dev/null 2>&1
        echo "✅ 패키지 업데이트 완료"
    fi

    # 서비스 등록 및 시작
    systemctl daemon-reload
    systemctl enable ansible-api-server
    systemctl restart ansible-api-server
    sleep 3
    
    # 상태 확인
    systemctl status ansible-api-server --no-pager | head -10
EOF
echo ""

# 6. 방화벽 포트 열기
echo -e "${YELLOW}[6/6] 방화벽 설정...${NC}"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << EOF
    firewall-cmd --add-port=${API_PORT}/tcp --permanent 2>/dev/null || echo "포트 추가 실패 (이미 있을 수 있음)"
    firewall-cmd --reload 2>/dev/null || echo "방화벽 재시작 실패"
    echo "✅ 방화벽 설정 완료"
EOF
echo ""

# 7. 최종 확인
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}배포 완료!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "서버 정보:"
echo "  - 브랜치: $CURRENT_BRANCH"
echo "  - 포트: ${API_PORT}"
echo "  - API 서버: http://115.85.181.103:${API_PORT}"
echo "  - 리포트: http://115.85.181.103:${API_PORT}/api/report"
echo ""
echo "⚠️  ACG에서 포트 ${API_PORT} 허용 필요!"
echo ""
