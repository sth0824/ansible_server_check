#!/bin/bash
# API 서버를 백그라운드로 실행하는 스크립트
# 브랜치별로 다른 포트 사용: develop=8000, UI_sunmin=8001

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
API_DIR="$SCRIPT_DIR/api_server"
LOG_FILE="$SCRIPT_DIR/api_server.log"
PID_FILE="$SCRIPT_DIR/api_server.pid"

# 현재 브랜치 확인
CURRENT_BRANCH=$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null || echo "develop")

# 브랜치별 포트 설정
if [ "$CURRENT_BRANCH" = "UI_sunmin" ]; then
    PORT=8001
elif [ "$CURRENT_BRANCH" = "develop" ]; then
    PORT=8000
else
    # 기본값
    PORT=8000
fi

echo "🌿 현재 브랜치: $CURRENT_BRANCH"
echo "🔌 사용 포트: $PORT"

cd "$API_DIR"

# 이미 실행 중인지 확인
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p $OLD_PID > /dev/null 2>&1; then
        echo "⚠️  API 서버가 이미 실행 중입니다 (PID: $OLD_PID)"
        echo "   종료하려면: ./stop_api_server.sh"
        exit 1
    else
        # PID 파일은 있지만 프로세스가 없음 (비정상 종료)
        rm -f "$PID_FILE"
    fi
fi

# 가상환경 활성화
if [ -d "venv" ]; then
    source venv/bin/activate
    echo "✅ 가상환경 활성화 완료"
else
    echo "❌ 가상환경이 없습니다. venv 디렉토리를 확인하세요."
    exit 1
fi

# 포트 사용 중인지 확인
if lsof -ti:$PORT > /dev/null 2>&1 || fuser $PORT/tcp > /dev/null 2>&1; then
    echo "⚠️  포트 $PORT가 이미 사용 중입니다"
    echo "   다른 프로세스를 종료하거나 다른 브랜치로 전환하세요"
    exit 1
fi

# API 서버 백그라운드 실행 (포트를 환경변수로 전달)
echo "🚀 API 서버 시작 중... (포트: $PORT)"
export API_PORT=$PORT

# nohup과 setsid를 사용하여 완전히 분리된 백그라운드 프로세스로 실행
# 터미널을 닫아도 계속 실행됨
nohup setsid python3 main.py > "$LOG_FILE" 2>&1 < /dev/null &
API_PID=$!

# 프로세스가 제대로 시작되었는지 확인
sleep 1
if ! ps -p $API_PID > /dev/null 2>&1; then
    echo "❌ 서버 프로세스 시작 실패"
    echo "📝 로그 확인: tail -20 $LOG_FILE"
    exit 1
fi

# PID 저장
echo $API_PID > "$PID_FILE"

# 서버 시작 대기
echo "⏳ 서버 준비 대기 중..."
sleep 3

# 서버 상태 확인
if curl -s http://localhost:$PORT/api/health > /dev/null 2>&1; then
    echo "✅ API 서버가 정상적으로 실행 중입니다!"
    echo "   브랜치: $CURRENT_BRANCH"
    echo "   PID: $API_PID"
    echo "   포트: $PORT"
    echo "   주소: http://192.168.0.18:$PORT"
    echo "   리포트: http://192.168.0.18:$PORT/api/report"
    echo "   API 문서: http://192.168.0.18:$PORT/docs"
    echo "   로그 파일: $LOG_FILE"
    echo ""
    echo "종료하려면: ./stop_api_server.sh"
else
    echo "⚠️  서버 시작 확인 실패. 로그를 확인하세요:"
    echo "   tail -f $LOG_FILE"
fi

