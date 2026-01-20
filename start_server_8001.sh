#!/bin/bash
# 포트 8001로 서버 실행 (UI_sunmin 브랜치용)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# UI_sunmin 브랜치로 전환
echo "🌿 UI_sunmin 브랜치로 전환 중..."
git checkout UI_sunmin 2>/dev/null || echo "⚠️  이미 UI_sunmin 브랜치입니다"

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
echo "✅ 현재 브랜치: $CURRENT_BRANCH"

# 모든 스크립트에 실행 권한 부여
echo "🔧 스크립트 실행 권한 부여 중..."
chmod +x *.sh

# 포트 8001 사용 확인
PORT=8001
echo ""
echo "🔌 사용 포트: $PORT"

# 포트 사용 중인지 확인
if lsof -ti:$PORT > /dev/null 2>&1 || fuser $PORT/tcp > /dev/null 2>&1; then
    echo "⚠️  포트 $PORT가 이미 사용 중입니다"
    echo "   기존 프로세스를 종료하시겠습니까? (y/n)"
    read -r response
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        lsof -ti:$PORT | xargs kill -9 2>/dev/null
        fuser $PORT/tcp -k 2>/dev/null
        sleep 2
        echo "✅ 기존 프로세스 종료 완료"
    else
        echo "❌ 서버 시작 취소"
        exit 1
    fi
fi

# 서버 시작
echo ""
echo "🚀 서버 시작 중... (포트: $PORT)"
API_PORT=$PORT bash start_api_server.sh

echo ""
echo "✅ 서버가 포트 $PORT로 실행되었습니다!"
echo "🌐 리포트 URL: http://192.168.0.18:$PORT/api/report"
