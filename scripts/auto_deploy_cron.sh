#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
cd "$SCRIPT_DIR"
LOG_FILE="$SCRIPT_DIR/logs/auto_deploy.log"
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
git fetch origin develop >/dev/null 2>&1
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/develop)
if [ "$LOCAL" != "$REMOTE" ]; then
    log "변경사항 발견 - 배포 시작"
    git pull origin develop && [ -f deploy_current_branch.sh ] && ./deploy_current_branch.sh >> "$LOG_FILE" 2>&1
fi
