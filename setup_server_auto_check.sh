#!/bin/bash
# 네이버 클라우드 서버 자동 점검 초기 설정 스크립트
# Ansible 설치, crontab 설정 등을 수행

set -e

# 서버 정보
SERVER_HOST="27.96.129.114"
SERVER_PORT="4433"
SERVER_USER="root"
SSH_KEY="/home/sth0824/.ssh/nimso2026.pem"
REMOTE_DIR="/opt/ansible-monitoring"

# 색상 출력
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}네이버 클라우드 서버 자동 점검 초기 설정${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 1. SSH 접속 테스트
echo -e "${YELLOW}[1/5] SSH 접속 테스트...${NC}"
if ! ssh -i "$SSH_KEY" -p "$SERVER_PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_HOST" "echo 'SSH 연결 성공'" > /dev/null 2>&1; then
    echo -e "${RED}❌ SSH 접속 실패 (핫스팟 연결 확인 필요)${NC}"
    exit 1
fi
echo -e "${GREEN}✅ SSH 접속 성공${NC}"
echo ""

# 2. Ansible 설치
echo -e "${YELLOW}[2/5] Ansible 설치 확인 및 설치...${NC}"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << EOF
    cd ${REMOTE_DIR}
    if [ -f "install_ansible.sh" ]; then
        chmod +x install_ansible.sh
        ./install_ansible.sh
    else
        echo "⚠️  install_ansible.sh 파일이 없습니다. 먼저 배포를 실행하세요."
        exit 1
    fi
EOF
echo ""

# 3. SSH 키 확인 및 테스트
echo -e "${YELLOW}[3/5] SSH 키 확인 및 테스트...${NC}"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << EOF
    if [ -f "${REMOTE_DIR}/.ssh/nimso2026.pem" ]; then
        echo "✅ SSH 키 파일 존재 확인"
        chmod 600 ${REMOTE_DIR}/.ssh/nimso2026.pem
        
        # SSH 접속 테스트 (자기 자신에게)
        echo "SSH 자기 자신 접속 테스트 중..."
        ssh -i ${REMOTE_DIR}/.ssh/nimso2026.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@127.0.0.1 "echo 'SSH 자기 자신 접속 성공'" 2>&1 || echo "⚠️  SSH 자기 자신 접속 테스트 실패 (SSH 키 설정 확인 필요)"
    else
        echo "⚠️  SSH 키 파일이 없습니다. 배포 스크립트를 먼저 실행하세요."
    fi
EOF
echo ""

# 4. 자동 점검 스크립트 실행 권한 부여
echo -e "${YELLOW}[4/5] 자동 점검 스크립트 설정...${NC}"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << EOF
    cd ${REMOTE_DIR}
    if [ -f "auto_check_navercloud.sh" ]; then
        chmod +x auto_check_navercloud.sh
        echo "✅ 자동 점검 스크립트 실행 권한 부여 완료"
    else
        echo "⚠️  auto_check_navercloud.sh 파일이 없습니다."
    fi
EOF
echo ""

# 5. Crontab 설정
echo -e "${YELLOW}[5/5] Crontab 설정...${NC}"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST" << 'EOF'
    CRON_JOB="0 7 * * * cd /opt/ansible-monitoring && /opt/ansible-monitoring/auto_check_navercloud.sh >> /opt/ansible-monitoring/logs/navercloud_cron.log 2>&1"
    
    # 기존 crontab 백업
    crontab -l > /tmp/crontab_backup_$(date +%Y%m%d_%H%M%S).txt 2>/dev/null || true
    
    # 기존 자동 점검 cron job 제거 (있다면)
    crontab -l 2>/dev/null | grep -v "auto_check_navercloud.sh" | crontab - 2>/dev/null || true
    
    # 새 cron job 추가
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    
    echo "✅ Crontab 설정 완료"
    echo ""
    echo "현재 crontab 설정:"
    crontab -l | grep -E "(auto_check|Ansible)" || echo "  (자동 점검 관련 항목 없음)"
EOF

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}초기 설정 완료!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "설정 내용:"
echo "  - Ansible 설치 완료"
echo "  - 자동 점검 스크립트 실행 권한 부여"
echo "  - Crontab 설정 완료 (매일 오전 7시 실행)"
echo ""
echo "확인 방법:"
echo "  - 서버에서 crontab 확인: ssh -i $SSH_KEY -p $SERVER_PORT $SERVER_USER@$SERVER_HOST 'crontab -l'"
echo "  - 수동 테스트: ssh -i $SSH_KEY -p $SERVER_PORT $SERVER_USER@$SERVER_HOST 'cd $REMOTE_DIR && ./auto_check_navercloud.sh'"
echo ""
