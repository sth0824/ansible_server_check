#!/bin/bash
# UI_sunmin 브랜치에서 포트 8001로 서버 시작

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

# 서버 시작 (자동으로 포트 8001 사용)
echo ""
echo "🚀 서버 시작 중... (포트: 8001)"
bash start_api_server.sh
