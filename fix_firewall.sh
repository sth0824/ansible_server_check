#!/bin/bash
# 서버 방화벽에서 포트 8000 열기 (원격 실행)

SERVER_HOST="27.96.129.114"
SERVER_PORT="1025"
SSH_KEY="/home/sth0824/.ssh/nimso2026.pem"

echo "=========================================="
echo "서버 방화벽 설정 (포트 8000 열기)"
echo "=========================================="
echo ""
echo "⚠️  핫스팟 연결이 필요합니다"
echo ""

# SSH 접속 테스트
echo "[1/3] SSH 접속 테스트..."
if ! ssh -i "$SSH_KEY" -p "$SERVER_PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$SERVER_HOST "echo 'SSH 연결 성공'" > /dev/null 2>&1; then
    echo "❌ SSH 접속 실패 (핫스팟 연결 확인 필요)"
    exit 1
fi
echo "✅ SSH 접속 성공"
echo ""

# 방화벽 설정
echo "[2/3] 방화벽 설정 중..."
ssh -i "$SSH_KEY" -p "$SERVER_PORT" root@$SERVER_HOST << 'EOF'
    # firewall-cmd 확인 및 설정
    if command -v firewall-cmd &> /dev/null; then
        echo "=== firewall-cmd 사용 ==="
        
        # 현재 포트 확인
        echo "현재 열린 포트:"
        firewall-cmd --list-ports 2>/dev/null || echo "없음"
        echo ""
        
        # 포트 8000 추가
        echo "포트 8000 추가 중..."
        firewall-cmd --add-port=8000/tcp --permanent 2>&1
        firewall-cmd --reload 2>&1
        
        # 확인
        echo ""
        echo "설정 후 열린 포트:"
        firewall-cmd --list-ports 2>/dev/null
        echo ""
        
        # 포트 8000 확인
        if firewall-cmd --list-ports 2>/dev/null | grep -q "8000"; then
            echo "✅ 포트 8000이 방화벽에 추가되었습니다"
        else
            echo "⚠️  포트 8000 추가 확인 필요"
        fi
    # iptables 사용
    elif command -v iptables &> /dev/null; then
        echo "=== iptables 사용 ==="
        
        # 포트 8000 규칙 추가
        iptables -I INPUT -p tcp --dport 8000 -j ACCEPT 2>&1
        
        # 규칙 저장 (CentOS)
        if command -v service &> /dev/null; then
            service iptables save 2>/dev/null || echo "iptables 저장 실패 (수동 저장 필요)"
        fi
        
        echo "✅ iptables 규칙 추가 완료"
        echo ""
        echo "포트 8000 규칙:"
        iptables -L -n | grep 8000 || echo "규칙 확인 실패"
    else
        echo "⚠️  방화벽 도구를 찾을 수 없습니다"
        echo "수동으로 확인이 필요합니다"
    fi
EOF

echo ""
echo "[3/3] 서비스 재시작 및 확인..."
ssh -i "$SSH_KEY" -p "$SERVER_PORT" root@$SERVER_HOST << 'EOF'
    # API 서버 재시작
    systemctl restart ansible-api-server
    sleep 3
    
    # 상태 확인
    echo "=== API 서버 상태 ==="
    systemctl status ansible-api-server --no-pager | head -10
    echo ""
    
    # 포트 리스닝 확인
    echo "=== 포트 8000 리스닝 확인 ==="
    ss -tlnp | grep 8000 || echo "포트 8000이 리스닝되지 않음"
    echo ""
    
    # 로컬 접속 테스트
    echo "=== 로컬 접속 테스트 ==="
    curl -s http://localhost:8000/api/health && echo "" || echo "로컬 접속 실패"
EOF

echo ""
echo "=========================================="
echo "완료!"
echo "=========================================="
echo ""
echo "외부 접속 테스트:"
echo "  http://27.96.129.114:8000/api/health"
echo "  http://27.96.129.114:8000/api/dashboard"
echo ""
