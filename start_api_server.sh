#!/bin/bash
# API 서버를 백그라운드로 실행하는 스크립트

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
API_DIR="$SCRIPT_DIR/api_server"
LOG_FILE="$SCRIPT_DIR/api_server.log"
PID_FILE="$SCRIPT_DIR/api_server.pid"

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

# API 서버 백그라운드 실행
echo "🚀 API 서버 시작 중..."
nohup python3 main.py > "$LOG_FILE" 2>&1 &
API_PID=$!

# PID 저장
echo $API_PID > "$PID_FILE"

# 서버 시작 대기
echo "⏳ 서버 준비 대기 중..."
sleep 3

# 서버 상태 확인
if curl -s http://localhost:8000/api/health > /dev/null 2>&1; then
    echo "✅ API 서버가 정상적으로 실행 중입니다!"
    echo "   PID: $API_PID"
    echo "   주소: http://localhost:8000"
    echo "   API 문서: http://localhost:8000/docs"
    echo "   로그 파일: $LOG_FILE"
    echo ""
    echo "종료하려면: ./stop_api_server.sh"
else
    echo "⚠️  서버 시작 확인 실패. 로그를 확인하세요:"
    echo "   tail -f $LOG_FILE"
fi

