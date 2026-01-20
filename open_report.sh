#!/bin/bash
# 결과 페이지를 브라우저에서 여는 스크립트
# 현재 브랜치에 따라 포트 자동 선택

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 현재 브랜치 확인
CURRENT_BRANCH=$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null || echo "develop")

# 브랜치별 포트 설정
if [ "$CURRENT_BRANCH" = "UI_sunmin" ]; then
    PORT=8001
elif [ "$CURRENT_BRANCH" = "develop" ]; then
    PORT=8000
else
    PORT=8000
fi

API_URL="http://192.168.0.18:$PORT/api/report"

echo "🌿 현재 브랜치: $CURRENT_BRANCH"
echo "🔌 사용 포트: $PORT"
echo "🔍 API 서버 상태 확인 중..."

# 서버 상태 확인
if curl -s http://192.168.0.18:$PORT/api/health > /dev/null 2>&1; then
    echo "✅ API 서버가 실행 중입니다"
    echo "🌐 브라우저에서 리포트 페이지 열기: $API_URL"
    
    # WSL에서 Windows 브라우저 열기
    if command -v cmd.exe > /dev/null 2>&1; then
        cmd.exe /c start "$API_URL" 2>/dev/null
    elif command -v wslview > /dev/null 2>&1; then
        wslview "$API_URL"
    elif command -v xdg-open > /dev/null 2>&1; then
        xdg-open "$API_URL"
    else
        echo "⚠️  브라우저를 자동으로 열 수 없습니다"
        echo "   수동으로 다음 URL을 열어주세요: $API_URL"
    fi
else
    echo "❌ API 서버가 실행 중이지 않습니다"
    echo "   먼저 서버를 시작하세요: ./start_api_server.sh"
    exit 1
fi
