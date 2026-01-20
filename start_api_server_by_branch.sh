#!/bin/bash
# 현재 브랜치에 따라 다른 포트로 API 서버를 실행하는 스크립트

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
API_DIR="$SCRIPT_DIR/api_server"
LOG_FILE="$SCRIPT_DIR/api_server.log"
PID_FILE="$SCRIPT_DIR/api_server.pid"

cd "$SCRIPT_DIR"

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# 브랜치별 포트 매핑
declare -A BRANCH_PORTS
BRANCH_PORTS["develop"]=8000
BRANCH_PORTS["UI_sunmin"]=8001
BRANCH_PORTS["main"]=8002

# 포트 결정
if [ -n "${BRANCH_PORTS[$CURRENT_BRANCH]}" ]; then
    PORT=${BRANCH_PORTS[$CURRENT_BRANCH]}
else
    # 기본 포트 (브랜치명의 해시값 기반으로 포트 생성)
    PORT=$((8000 + $(echo -n "$CURRENT_BRANCH" | md5sum | cut -c1-2 | sed 's/[^0-9]//g' | head -c 3) % 100))
fi

echo "🌿 현재 브랜치: $CURRENT_BRANCH"
echo "🔌 사용 포트: $PORT"

# 기존 서버 확인 (같은 포트 사용 중인지)
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p $OLD_PID > /dev/null 2>&1; then
        echo "⚠️  API 서버가 이미 실행 중입니다 (PID: $OLD_PID)"
        echo "   종료하려면: ./stop_api_server.sh"
        exit 1
    else
        rm -f "$PID_FILE"
    fi
fi

# 포트 사용 중인지 확인
if lsof -ti:$PORT > /dev/null 2>&1 || fuser $PORT/tcp > /dev/null 2>&1; then
    echo "⚠️  포트 $PORT가 이미 사용 중입니다"
    echo "   다른 프로세스를 종료하거나 다른 브랜치로 전환하세요"
    exit 1
fi

cd "$API_DIR"

# 가상환경 활성화
if [ -d "venv" ]; then
    source venv/bin/activate
    echo "✅ 가상환경 활성화 완료"
else
    echo "❌ 가상환경이 없습니다. venv 디렉토리를 확인하세요."
    exit 1
fi

# 환경변수로 포트 설정
export API_PORT=$PORT

# API 서버 백그라운드 실행 (포트를 환경변수로 전달)
echo "🚀 API 서버 시작 중... (포트: $PORT)"
nohup python3 -c "
import uvicorn
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath('main.py')))
from main import app
port = int(os.getenv('API_PORT', 8000))
uvicorn.run(app, host='0.0.0.0', port=port, reload=False)
" > "$LOG_FILE" 2>&1 &
API_PID=$!

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
    echo "   로그 파일: $LOG_FILE"
    echo ""
    echo "종료하려면: ./stop_api_server.sh"
else
    echo "⚠️  서버 시작 확인 실패. 로그를 확인하세요:"
    echo "   tail -f $LOG_FILE"
fi
