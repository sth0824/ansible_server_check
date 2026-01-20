#!/bin/bash
# API 서버 재시작 스크립트

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "🛑 기존 서버 종료 중..."

# PID 파일 확인 및 프로세스 종료
if [ -f "api_server.pid" ]; then
    PID=$(cat api_server.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "   PID $PID 종료 중..."
        kill $PID 2>/dev/null
        sleep 2
        if ps -p $PID > /dev/null 2>&1; then
            echo "   강제 종료 중..."
            kill -9 $PID 2>/dev/null
            sleep 1
        fi
    fi
    rm -f api_server.pid
    echo "✅ 기존 서버 종료 완료"
else
    echo "⚠️  PID 파일이 없습니다"
fi

# 포트 8000을 사용하는 다른 프로세스도 확인
echo "📋 포트 8000 사용 중인 프로세스 확인..."
PORT_PIDS=$(lsof -ti:8000 2>/dev/null || fuser 8000/tcp 2>/dev/null | awk '{print $1}' || echo "")
if [ ! -z "$PORT_PIDS" ]; then
    for PORT_PID in $PORT_PIDS; do
        echo "   PID $PORT_PID 종료 중..."
        kill -9 $PORT_PID 2>/dev/null
    done
    sleep 1
fi

echo ""
echo "🚀 새 서버 시작 중..."
bash start_api_server.sh
