#!/bin/bash
# 두 개의 API 서버를 동시에 실행하는 스크립트
# 포트 8000 (develop)과 포트 8001 (UI_sunmin)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
API_DIR="$SCRIPT_DIR/api_server"

# 포트별 설정 (PID파일:로그파일:포트:주소)
declare -A SERVER_CONFIG
SERVER_CONFIG[8000]="api_server_8000.pid:api_server_8000.log:8000:192.168.0.18"
SERVER_CONFIG[8001]="api_server_8001.pid:api_server_8001.log:8001:192.168.0.18"

echo "🚀 두 개의 API 서버를 시작합니다..."
echo "   포트 8000: develop 브랜치용"
echo "   포트 8001: UI_sunmin 브랜치용"
echo ""

cd "$API_DIR"

# 가상환경 확인
if [ ! -d "venv" ]; then
    echo "❌ 가상환경이 없습니다. venv 디렉토리를 확인하세요."
    exit 1
fi

source venv/bin/activate
echo "✅ 가상환경 활성화 완료"
echo ""

# 각 포트별로 서버 시작
for port in 8000 8001; do
    IFS=':' read -r pid_file log_file port_num server_addr <<< "${SERVER_CONFIG[$port]}"
    PID_FILE="$SCRIPT_DIR/$pid_file"
    LOG_FILE="$SCRIPT_DIR/$log_file"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔌 포트 $port 서버 시작 중..."
    
    # 기존 서버 확인
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if ps -p $OLD_PID > /dev/null 2>&1; then
            echo "⚠️  포트 $port 서버가 이미 실행 중입니다 (PID: $OLD_PID)"
            echo "   기존 서버를 종료하고 재시작합니다..."
            kill $OLD_PID 2>/dev/null
            sleep 2
            if ps -p $OLD_PID > /dev/null 2>&1; then
                kill -9 $OLD_PID 2>/dev/null
                sleep 1
            fi
            rm -f "$PID_FILE"
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    # 포트 사용 중인지 확인하고 기존 프로세스 종료
    PORT_PID=""
    if command -v lsof > /dev/null 2>&1; then
        PORT_PID=$(lsof -ti:$port 2>/dev/null)
    elif command -v fuser > /dev/null 2>&1; then
        PORT_PID=$(fuser $port/tcp 2>/dev/null | awk '{print $1}')
    fi
    
    if [ -n "$PORT_PID" ]; then
        echo "⚠️  포트 $port가 이미 사용 중입니다 (PID: $PORT_PID)"
        echo "   기존 프로세스를 종료합니다..."
        kill $PORT_PID 2>/dev/null
        sleep 2
        
        # 강제 종료가 필요한 경우
        if ps -p $PORT_PID > /dev/null 2>&1; then
            echo "   강제 종료 중..."
            kill -9 $PORT_PID 2>/dev/null
            sleep 1
        fi
        
        echo "   ✅ 기존 프로세스 종료 완료"
    fi
    
    # 환경변수로 포트 설정
    export API_PORT=$port
    
    # API 서버 백그라운드 실행
    echo "   서버 시작 중..."
    nohup python3 -c "
import uvicorn
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath('main.py')))
from main import app
port = int(os.getenv('API_PORT', $port))
uvicorn.run(app, host='0.0.0.0', port=port, reload=False)
" > "$LOG_FILE" 2>&1 &
    API_PID=$!
    
    # PID 저장
    echo $API_PID > "$PID_FILE"
    
    # 서버 시작 대기
    sleep 3
    
    # 서버 상태 확인
    if curl -s http://localhost:$port/api/health > /dev/null 2>&1; then
        echo "✅ 포트 $port 서버가 정상적으로 실행 중입니다!"
        echo "   PID: $API_PID"
        echo "   주소: http://${server_addr}:$port"
        echo "   리포트: http://${server_addr}:$port/api/report"
        echo "   로그: $LOG_FILE"
    else
        echo "⚠️  포트 $port 서버 시작 확인 실패"
        echo "   로그 확인: tail -20 $LOG_FILE"
    fi
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 서버 상태 요약:"
echo ""
for port in 8000 8001; do
    IFS=':' read -r pid_file log_file port_num server_addr <<< "${SERVER_CONFIG[$port]}"
    PID_FILE="$SCRIPT_DIR/$pid_file"
    
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null 2>&1; then
            if curl -s http://localhost:$port/api/health > /dev/null 2>&1; then
                echo "✅ 포트 $port: 실행 중 (PID: $PID)"
                echo "   주소: http://${server_addr}:$port/api/report"
            else
                echo "⚠️  포트 $port: 프로세스는 있지만 응답 없음 (PID: $PID)"
            fi
        else
            echo "❌ 포트 $port: 실행 중이 아님"
        fi
    else
        echo "❌ 포트 $port: 실행 중이 아님"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  Windows에서 접속하려면 포트 포워딩이 필요할 수 있습니다:"
echo "   PowerShell(관리자)에서 실행:"
echo "   .\\setup_port_forwarding.ps1"
echo ""
echo "📝 종료하려면: ./stop_both_servers.sh"
echo "📝 개별 종료: ./stop_api_server.sh 8000 또는 ./stop_api_server.sh 8001"
