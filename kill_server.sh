#!/bin/bash
# 서버 종료 스크립트 (권한 부여 포함)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 모든 스크립트에 실행 권한 부여
chmod +x *.sh

# 서버 종료
if [ -f "$SCRIPT_DIR/api_server.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/api_server.pid")
    if ps -p $PID > /dev/null 2>&1; then
        echo "🛑 API 서버 종료 중... (PID: $PID)"
        kill $PID 2>/dev/null
        
        # 종료 대기
        sleep 2
        
        if ps -p $PID > /dev/null 2>&1; then
            echo "⚠️  정상 종료 실패. 강제 종료 중..."
            kill -9 $PID 2>/dev/null
            sleep 1
        fi
        
        if ! ps -p $PID > /dev/null 2>&1; then
            rm -f "$SCRIPT_DIR/api_server.pid"
            echo "✅ API 서버가 종료되었습니다."
        else
            echo "❌ 서버 종료 실패"
            exit 1
        fi
    else
        echo "⚠️  프로세스가 실행 중이지 않습니다. PID 파일을 삭제합니다."
        rm -f "$SCRIPT_DIR/api_server.pid"
    fi
else
    echo "⚠️  PID 파일이 없습니다."
    
    # 포트로 확인하여 종료
    echo "📋 포트 8000, 8001 사용 중인 프로세스 확인..."
    for PORT in 8000 8001; do
        PID=$(lsof -ti:$PORT 2>/dev/null || fuser $PORT/tcp 2>/dev/null | awk '{print $1}')
        if [ ! -z "$PID" ]; then
            echo "   포트 $PORT 사용 중인 프로세스 발견 (PID: $PID)"
            kill -9 $PID 2>/dev/null
            echo "   ✅ 포트 $PORT 프로세스 종료 완료"
        fi
    done
fi
