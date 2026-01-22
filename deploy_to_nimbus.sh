#!/bin/bash
# nimbus-server에 API 서버 및 DB 서버 배포 스크립트

set -e

# 서버 정보
SERVER_HOST="27.96.129.114"
SERVER_PORT="1025"
SERVER_USER="root"
SSH_KEY="/home/sth0824/.ssh/nimso2026.pem"
REMOTE_DIR="/opt/ansible-monitoring"

# 색상 출력
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}nimbus-server 배포 시작${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 1. SSH 접속 테스트
echo -e "${YELLOW}[1/6] SSH 접속 테스트...${NC}"
SSH_ERROR=$(ssh -i "$SSH_KEY" -p "$SERVER_PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SERVER_USER@$SERVER_HOST" "echo 'SSH 연결 성공'" 2>&1)
SSH_EXIT_CODE=$?

if [ $SSH_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ SSH 접속 성공${NC}"
else
    echo -e "${RED}❌ SSH 접속 실패${NC}"
    echo -e "${RED}오류 내용:${NC}"
    echo "$SSH_ERROR"
    echo ""
    echo "확인 사항:"
    echo "  - 키 파일: $SSH_KEY"
    echo "  - 서버 주소: $SERVER_HOST"
    echo "  - 포트: $SERVER_PORT"
    echo "  - 사용자: $SERVER_USER"
    exit 1
fi
echo ""

# 2. 서버 디렉토리 생성
echo -e "${YELLOW}[2/6] 서버 디렉토리 생성...${NC}"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << 'EOF'
    mkdir -p /opt/ansible-monitoring/api_server
    mkdir -p /opt/ansible-monitoring/logs
    echo "✅ 디렉토리 생성 완료"
EOF
echo ""

# 3. 프로젝트 파일 업로드
echo -e "${YELLOW}[3/6] 프로젝트 파일 업로드...${NC}"
echo "   - API 서버 파일 업로드 중..."

# API 서버 파일만 업로드 (필요한 파일만)
rsync -avz -e "ssh -i $SSH_KEY -p $SERVER_PORT" \
    --exclude='venv' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.git' \
    --exclude='check_results.db' \
    --exclude='*.log' \
    ./api_server/ "$SERVER_USER@$SERVER_HOST:$REMOTE_DIR/api_server/"

echo -e "${GREEN}✅ 파일 업로드 완료${NC}"
echo ""

# 4. 설치 스크립트 업로드
echo -e "${YELLOW}[4/6] 설치 스크립트 업로드...${NC}"
scp -i "$SSH_KEY" -P "$SERVER_PORT" \
    ./deploy_install.sh \
    "$SERVER_USER@$SERVER_HOST:$REMOTE_DIR/"

scp -i "$SSH_KEY" -P "$SERVER_PORT" \
    ./ansible-api-server.service \
    "$SERVER_USER@$SERVER_HOST:/tmp/"

# PostgreSQL은 기본 systemd 서비스이므로 별도 서비스 파일 불필요

echo -e "${GREEN}✅ 설치 스크립트 업로드 완료${NC}"
echo ""

# 5. 서버에서 설치 실행
echo -e "${YELLOW}[5/6] 서버에서 설치 실행...${NC}"
echo "   (이 작업은 몇 분이 걸릴 수 있습니다)"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << EOF
    cd $REMOTE_DIR
    chmod +x deploy_install.sh
    bash deploy_install.sh
EOF
echo ""

# 6. 서비스 시작
echo -e "${YELLOW}[6/6] 서비스 시작...${NC}"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << 'EOF'
    systemctl daemon-reload
    systemctl enable ansible-api-server
    systemctl enable postgresql
    systemctl restart postgresql
    sleep 3
    systemctl restart ansible-api-server
    sleep 2
    
    # 상태 확인
    echo ""
    echo "=== 서비스 상태 ==="
    systemctl status ansible-api-server --no-pager -l | head -10
    echo ""
    systemctl status postgresql --no-pager -l | head -10
EOF
echo ""

# 7. 최종 확인
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}배포 완료!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "서버 정보:"
echo "  - 호스트: $SERVER_HOST"
echo "  - API 서버: http://$SERVER_HOST:8000"
echo "  - 대시보드: http://$SERVER_HOST:8000/api/dashboard"
echo ""
echo "다음 단계:"
echo "  1. ACG에서 포트 8000 허용 확인"
echo "  2. http://$SERVER_HOST:8000 접속 테스트"
echo "  3. 로그 확인: ssh로 접속 후 'journalctl -u ansible-api-server -f'"
echo ""
