#!/bin/bash
# Git pull 후 API 서버 자동 재시작 스크립트
# 중앙 서버(192.168.0.18)에서 사용

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

# UI_sunmin 브랜치에서는 자동 업데이트 비활성화
if [ "$CURRENT_BRANCH" = "UI_sunmin" ]; then
    echo "⚠️  UI_sunmin 브랜치에서는 자동 업데이트가 비활성화되어 있습니다."
    exit 0
fi

# develop 브랜치가 아니면 실행하지 않음
if [ "$CURRENT_BRANCH" != "develop" ]; then
    echo "⚠️  develop 브랜치가 아니므로 자동 업데이트를 건너뜁니다. (현재: $CURRENT_BRANCH)"
    exit 0
fi

echo "🔄 코드 업데이트 및 서버 재시작 중..."
echo ""

# 1. Git pull
echo "📥 Git pull 실행 중..."
git pull origin develop

if [ $? -ne 0 ]; then
    echo "❌ Git pull 실패"
    exit 1
fi

echo "✅ 코드 업데이트 완료"
echo ""

# 2. API 서버 재시작
echo "🔄 API 서버 재시작 중..."

# 서버 종료
if [ -f "$SCRIPT_DIR/api_server.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/api_server.pid")
    if ps -p $PID > /dev/null 2>&1; then
        echo "   기존 서버 종료 중... (PID: $PID)"
        kill $PID 2>/dev/null
        sleep 2
        if ps -p $PID > /dev/null 2>&1; then
            kill -9 $PID 2>/dev/null
        fi
        rm -f "$SCRIPT_DIR/api_server.pid"
    fi
fi

# 서버 시작
echo "   새 서버 시작 중..."
cd "$SCRIPT_DIR"
./start_api_server.sh

echo ""
echo "✅ 업데이트 및 재시작 완료!"
echo "   API 서버: http://192.168.0.18:8000"
