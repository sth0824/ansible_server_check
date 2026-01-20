#!/bin/bash
# 연결 테스트 스크립트

echo "🔍 연결 테스트 중..."
echo ""

# WSL IP
WSL_IP=$(hostname -I | awk '{print $1}')
echo "📡 WSL IP: $WSL_IP"
echo ""

# 1. 로컬 연결 테스트
echo "1️⃣ 로컬 연결 테스트 (localhost:8001):"
if curl -s http://localhost:8001/api/health > /dev/null 2>&1; then
    echo "   ✅ 성공"
    curl -s http://localhost:8001/api/health | head -3
else
    echo "   ❌ 실패"
fi

echo ""

# 2. WSL IP 연결 테스트
echo "2️⃣ WSL IP 연결 테스트 ($WSL_IP:8001):"
if curl -s http://$WSL_IP:8001/api/health > /dev/null 2>&1; then
    echo "   ✅ 성공"
    curl -s http://$WSL_IP:8001/api/health | head -3
else
    echo "   ❌ 실패"
fi

echo ""

# 3. 포트 리스닝 확인
echo "3️⃣ 포트 8001 리스닝 확인:"
if lsof -i:8001 > /dev/null 2>&1; then
    echo "   ✅ 포트 8001이 리스닝 중입니다"
    lsof -i:8001 | head -3
else
    echo "   ❌ 포트 8001이 리스닝 중이 아닙니다"
fi

echo ""

# 4. Windows 호스트 IP 확인
echo "4️⃣ Windows 호스트 IP 확인:"
echo "   💡 Windows PowerShell에서 실행:"
echo "      ipconfig | findstr IPv4"
echo ""

echo "🌐 접속 가능한 URL:"
echo "   - WSL 내부: http://localhost:8001/api/report"
echo "   - WSL IP: http://$WSL_IP:8001/api/report"
echo "   - Windows 호스트 IP: http://192.168.0.18:8001/api/report (포트 포워딩 필요)"
echo ""
echo "⚠️  Windows에서 접속하려면:"
echo "   1. Windows PowerShell(관리자)에서 포트 포워딩 설정"
echo "   2. 또는 WSL IP로 직접 접속: http://$WSL_IP:8001/api/report"
