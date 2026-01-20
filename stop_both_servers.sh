#!/bin/bash
# 두 개의 API 서버를 모두 종료하는 스크립트

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "🛑 두 개의 API 서버를 종료합니다..."
echo ""

# 포트별 PID 파일
PID_FILES=("$SCRIPT_DIR/api_server_8000.pid" "$SCRIPT_DIR/api_server_8001.pid")
PORTS=(8000 8001)

for i in "${!PID_FILES[@]}"; do
    PID_FILE="${PID_FILES[$i]}"
    PORT="${PORTS[$i]}"
    
    if [ ! -f "$PID_FILE" ]; then
        echo "⚠️  포트 $PORT: PID 파일이 없습니다. 서버가 실행 중이지 않을 수 있습니다."
        continue
    fi
    
    PID=$(cat "$PID_FILE")
    
    if ps -p $PID > /dev/null 2>&1; then
        echo "🛑 포트 $PORT 서버 종료 중... (PID: $PID)"
        kill $PID
        
        # 종료 대기
        sleep 2
        
        if ps -p $PID > /dev/null 2>&1; then
            echo "⚠️  정상 종료 실패. 강제 종료 중..."
            kill -9 $PID
            sleep 1
        fi
        
        if ! ps -p $PID > /dev/null 2>&1; then
            rm -f "$PID_FILE"
            echo "✅ 포트 $PORT 서버가 종료되었습니다."
        else
            echo "❌ 포트 $PORT 서버 종료 실패"
        fi
    else
        echo "⚠️  포트 $PORT: 프로세스가 실행 중이지 않습니다. PID 파일을 삭제합니다."
        rm -f "$PID_FILE"
    fi
    echo ""
done

# 포트를 사용하는 다른 프로세스도 확인
for port in 8000 8001; do
    PORT_PID=""
    if command -v lsof > /dev/null 2>&1; then
        PORT_PID=$(lsof -ti:$port 2>/dev/null)
    elif command -v fuser > /dev/null 2>&1; then
        PORT_PID=$(fuser $port/tcp 2>/dev/null | awk '{print $1}')
    fi
    
    if [ -n "$PORT_PID" ]; then
        echo "⚠️  포트 $port를 사용하는 추가 프로세스 발견 (PID: $PORT_PID)"
        echo "   종료하시겠습니까? (y/n)"
        read -r response
        if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
            kill $PORT_PID 2>/dev/null
            sleep 1
            if ps -p $PORT_PID > /dev/null 2>&1; then
                kill -9 $PORT_PID 2>/dev/null
            fi
            echo "✅ 프로세스 종료 완료"
        fi
    fi
done

echo "✅ 모든 서버 종료 완료"
