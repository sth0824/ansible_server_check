#!/bin/bash
# 네이버 클라우드 서버 상태 확인 스크립트

SERVER_HOST="27.96.129.114"
SERVER_PORT="1025"
SSH_KEY="/home/sth0824/.ssh/nimso2026.pem"

echo "=========================================="
echo "nimbus-server 상태 확인"
echo "=========================================="
echo ""

# 핫스팟 연결 필요 안내
echo "⚠️  이 스크립트는 핫스팟 연결이 필요합니다 (포트 1025)"
echo ""

# SSH 접속 테스트
echo "[1/4] SSH 접속 테스트..."
if ssh -i "$SSH_KEY" -p "$SERVER_PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$SERVER_HOST "echo 'SSH 연결 성공'" > /dev/null 2>&1; then
    echo "✅ SSH 접속 성공"
else
    echo "❌ SSH 접속 실패 (핫스팟 연결 확인 필요)"
    exit 1
fi
echo ""

# API 서버 상태
echo "[2/4] API 서버 상태 확인..."
ssh -i "$SSH_KEY" -p "$SERVER_PORT" root@$SERVER_HOST << 'EOF'
    echo "=== systemd 서비스 상태 ==="
    systemctl status ansible-api-server --no-pager | head -10
    echo ""
    echo "=== 포트 8000 리스닝 확인 ==="
    ss -tlnp | grep 8000 || echo "포트 8000이 리스닝되지 않음"
    echo ""
    echo "=== 로컬 접속 테스트 ==="
    curl -s http://localhost:8000/api/health || echo "로컬 접속 실패"
    echo ""
EOF

# 외부 접속 테스트
echo "[3/4] 외부 접속 테스트..."
EXTERNAL_TEST=$(curl -s --connect-timeout 5 http://27.96.129.114:8000/api/health 2>&1)
if [[ "$EXTERNAL_TEST" == *"healthy"* ]]; then
    echo "✅ 외부 접속 성공"
    echo "응답: $EXTERNAL_TEST"
else
    echo "❌ 외부 접속 실패"
    echo "응답: $EXTERNAL_TEST"
    echo ""
    echo "가능한 원인:"
    echo "  1. 서버 방화벽(firewall)에서 포트 8000 차단"
    echo "  2. 네트워크 문제"
fi
echo ""

# 서버 방화벽 확인
echo "[4/4] 서버 방화벽 확인..."
ssh -i "$SSH_KEY" -p "$SERVER_PORT" root@$SERVER_HOST << 'EOF'
    if command -v firewall-cmd &> /dev/null; then
        echo "=== firewall-cmd 상태 ==="
        firewall-cmd --list-ports 2>/dev/null || echo "firewall-cmd 사용 불가"
    elif command -v iptables &> /dev/null; then
        echo "=== iptables 규칙 (포트 8000) ==="
        iptables -L -n | grep 8000 || echo "포트 8000 규칙 없음"
    else
        echo "방화벽 도구를 찾을 수 없음"
    fi
EOF

echo ""
echo "=========================================="
echo "확인 완료"
echo "=========================================="
