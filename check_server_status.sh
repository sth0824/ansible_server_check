#!/bin/bash
# 서버 상태 확인 스크립트

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "🔍 서버 상태 확인 중..."
echo ""

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
echo "🌿 현재 브랜치: $CURRENT_BRANCH"

# 브랜치별 포트 확인
if [ "$CURRENT_BRANCH" = "UI_sunmin" ]; then
    PORT=8001
elif [ "$CURRENT_BRANCH" = "develop" ]; then
    PORT=8000
else
    PORT=8000
fi

echo "🔌 예상 포트: $PORT"
echo ""

# PID 파일 확인
if [ -f "$SCRIPT_DIR/api_server.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/api_server.pid")
    echo "📋 PID 파일: $PID"
    if ps -p $PID > /dev/null 2>&1; then
        echo "✅ 프로세스 실행 중 (PID: $PID)"
    else
        echo "❌ 프로세스가 실행 중이지 않습니다"
    fi
else
    echo "⚠️  PID 파일이 없습니다"
fi

echo ""

# 포트 사용 확인
echo "📡 포트 $PORT 사용 확인:"
if lsof -ti:$PORT > /dev/null 2>&1; then
    echo "✅ 포트 $PORT가 사용 중입니다"
    lsof -i:$PORT
elif fuser $PORT/tcp > /dev/null 2>&1; then
    echo "✅ 포트 $PORT가 사용 중입니다"
    fuser $PORT/tcp
else
    echo "❌ 포트 $PORT가 사용 중이지 않습니다"
fi

echo ""

# 서버 헬스 체크
echo "🏥 서버 헬스 체크:"
if curl -s http://localhost:$PORT/api/health > /dev/null 2>&1; then
    echo "✅ 서버가 정상적으로 응답합니다"
    curl -s http://localhost:$PORT/api/health | head -5
else
    echo "❌ 서버가 응답하지 않습니다"
fi

echo ""

# 최근 로그 확인
if [ -f "$SCRIPT_DIR/api_server.log" ]; then
    echo "📝 최근 로그 (마지막 20줄):"
    tail -20 "$SCRIPT_DIR/api_server.log"
else
    echo "⚠️  로그 파일이 없습니다"
fi
