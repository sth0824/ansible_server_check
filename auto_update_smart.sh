#!/bin/bash
# 스마트 자동 업데이트: 변경사항이 있을 때만 pull 및 재시작
# 중앙 서버(192.168.0.18)에서 Cron Job으로 사용

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

LOG_FILE="$SCRIPT_DIR/api_auto_update.log"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

# UI_sunmin 브랜치에서는 자동 업데이트 비활성화
if [ "$CURRENT_BRANCH" = "UI_sunmin" ]; then
    log "⚠️  UI_sunmin 브랜치에서는 자동 업데이트가 비활성화되어 있습니다."
    exit 0
fi

log "🔄 코드 업데이트 체크 시작... (현재 브랜치: $CURRENT_BRANCH)"

# 1. 현재 브랜치에 해당하는 원격 브랜치 fetch (develop 브랜치가 아닌 현재 브랜치 기준)
# 현재 브랜치가 develop이 아니면 develop을 fetch하지 않음
if [ "$CURRENT_BRANCH" = "develop" ]; then
    # develop 브랜치인 경우에만 develop을 fetch
    log "📥 원격 develop 브랜치 정보 가져오기..."
    git fetch origin develop > /dev/null 2>&1
    
    # 2. 로컬과 원격의 차이 확인
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/develop)
else
    # 다른 브랜치에서는 develop을 fetch하지 않음
    log "⚠️  develop 브랜치가 아니므로 자동 업데이트를 건너뜁니다. (현재: $CURRENT_BRANCH)"
    exit 0
fi

if [ "$LOCAL" = "$REMOTE" ]; then
    log "✅ 최신 코드입니다. 업데이트 불필요."
    exit 0
fi

log "📥 변경사항 발견! 업데이트 시작..."

# 3. Git pull
git pull origin develop

if [ $? -ne 0 ]; then
    log "❌ Git pull 실패 - 충돌이 발생했을 수 있습니다"
    exit 1
fi

log "✅ 코드 업데이트 완료"

# 4. API 서버 재시작
log "🔄 API 서버 재시작 중..."

# 서버 종료
if [ -f "$SCRIPT_DIR/api_server.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/api_server.pid")
    if ps -p $PID > /dev/null 2>&1; then
        log "   기존 서버 종료 중... (PID: $PID)"
        kill $PID 2>/dev/null
        sleep 2
        if ps -p $PID > /dev/null 2>&1; then
            kill -9 $PID 2>/dev/null
        fi
        rm -f "$SCRIPT_DIR/api_server.pid"
    fi
fi

# 서버 시작
log "   새 서버 시작 중..."
cd "$SCRIPT_DIR"
./start_api_server.sh >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "✅ 업데이트 및 재시작 완료!"
else
    log "❌ 서버 재시작 실패"
    exit 1
fi
