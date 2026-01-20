#!/bin/bash
# 모든 스크립트에 실행 권한 부여 후 서버 시작

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 모든 스크립트에 실행 권한 부여
echo "🔧 스크립트 실행 권한 부여 중..."
chmod +x *.sh
echo "✅ 권한 부여 완료"
echo ""

# 서버 시작
echo "🚀 서버 시작 중..."
bash start_api_server.sh
