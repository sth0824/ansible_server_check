#!/bin/bash
# 완전한 백그라운드 실행 (터미널 종료해도 계속 실행)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 모든 스크립트에 실행 권한 부여
chmod +x *.sh

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "develop")

# 브랜치별 포트 설정
if [ "$CURRENT_BRANCH" = "UI_sunmin" ]; then
    PORT=8001
elif [ "$CURRENT_BRANCH" = "develop" ]; then
    PORT=8000
else
    PORT=8000
fi

echo "🌿 현재 브랜치: $CURRENT_BRANCH"
echo "🔌 사용 포트: $PORT"
echo ""

# 기존 서버 종료
if [ -f "$SCRIPT_DIR/api_server.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/api_server.pid")
    if ps -p $PID > /dev/null 2>&1; then
        echo "🛑 기존 서버 종료 중..."
        kill $PID 2>/dev/null
        sleep 2
        kill -9 $PID 2>/dev/null
    fi
    rm -f "$SCRIPT_DIR/api_server.pid"
fi

# 포트 사용 중인 프로세스 종료
lsof -ti:$PORT | xargs kill -9 2>/dev/null
fuser $PORT/tcp -k 2>/dev/null
sleep 2

# 서버 시작 (완전한 백그라운드)
echo "🚀 서버 백그라운드 시작 중..."
cd "$SCRIPT_DIR/api_server"

# 가상환경 활성화
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# nohup, setsid, disown을 사용하여 완전히 분리
export API_PORT=$PORT
nohup setsid python3 main.py > "$SCRIPT_DIR/api_server.log" 2>&1 < /dev/null &
API_PID=$!

# PID 저장
echo $API_PID > "$SCRIPT_DIR/api_server.pid"

# 프로세스 분리 확인
disown -h $API_PID 2>/dev/null

# 서버 시작 대기
echo "⏳ 서버 준비 대기 중..."
sleep 5

# 서버 상태 확인
if curl -s http://localhost:$PORT/api/health > /dev/null 2>&1; then
    echo "✅ 서버가 백그라운드에서 정상적으로 실행 중입니다!"
    echo "   브랜치: $CURRENT_BRANCH"
    echo "   PID: $API_PID"
    echo "   포트: $PORT"
    echo "   리포트: http://192.168.0.18:$PORT/api/report"
    echo ""
    echo "💡 터미널을 닫아도 서버는 계속 실행됩니다!"
    echo "   종료하려면: ./stop_api_server.sh"
    echo "   로그 확인: tail -f api_server.log"
else
    echo "⚠️  서버 시작 확인 실패"
    echo "   로그 확인: tail -20 api_server.log"
fi
