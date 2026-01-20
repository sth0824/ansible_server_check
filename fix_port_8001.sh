#!/bin/bash
# 포트 8001 서버 문제 해결 스크립트

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "🔧 포트 8001 서버 문제 해결 중..."
echo ""

# 1. 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
echo "🌿 현재 브랜치: $CURRENT_BRANCH"

if [ "$CURRENT_BRANCH" != "UI_sunmin" ]; then
    echo "⚠️  UI_sunmin 브랜치로 전환 중..."
    git checkout UI_sunmin
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
fi

# 2. 기존 서버 종료
echo ""
echo "🛑 기존 서버 종료 중..."
if [ -f "$SCRIPT_DIR/api_server.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/api_server.pid")
    kill $PID 2>/dev/null
    kill -9 $PID 2>/dev/null
    rm -f "$SCRIPT_DIR/api_server.pid"
fi

# 포트 8001 사용 중인 프로세스 종료
lsof -ti:8001 | xargs kill -9 2>/dev/null
fuser 8001/tcp -k 2>/dev/null
sleep 2

# 3. 모든 스크립트에 실행 권한 부여
echo "🔧 스크립트 실행 권한 부여 중..."
chmod +x *.sh

# 4. 서버 재시작
echo ""
echo "🚀 서버 재시작 중... (포트: 8001)"
export API_PORT=8001
cd "$SCRIPT_DIR/api_server"

# 가상환경 활성화
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# 서버 시작
cd "$SCRIPT_DIR"
bash start_api_server.sh

# 5. 서버 상태 확인
echo ""
echo "⏳ 서버 준비 대기 중..."
sleep 5

echo ""
echo "🔍 서버 상태 확인:"
if curl -s http://localhost:8001/api/health > /dev/null 2>&1; then
    echo "✅ 서버가 정상적으로 실행 중입니다!"
    echo ""
    echo "🌐 접속 URL:"
    echo "   - 로컬: http://localhost:8001/api/report"
    echo "   - 네트워크: http://192.168.0.18:8001/api/report"
    echo ""
    echo "⚠️  만약 네트워크에서 접속이 안 되면:"
    echo "   1. WSL IP 확인: hostname -I"
    echo "   2. Windows 방화벽 확인"
    echo "   3. 포트 포워딩 설정 확인"
else
    echo "❌ 서버가 응답하지 않습니다"
    echo "📝 로그 확인: tail -f api_server.log"
fi
