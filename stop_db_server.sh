#!/bin/bash
# DB 서버 중지 스크립트
# API 서버에서 사용하는 PostgreSQL 데이터베이스 서버를 중지합니다

echo "=========================================="
echo "DB 서버 중지"
echo "=========================================="
echo ""

# PostgreSQL 버전 확인
PG_VERSION=$(psql --version 2>/dev/null | grep -oP '\d+' | head -1)
if [ -z "$PG_VERSION" ]; then
    PG_VERSION="16"
fi

echo "📋 PostgreSQL 버전: $PG_VERSION"
echo ""

# PostgreSQL 클러스터 중지 시도
echo "🛑 PostgreSQL 클러스터 중지 중..."
if command -v pg_ctlcluster &> /dev/null; then
    sudo pg_ctlcluster ${PG_VERSION} main stop 2>/dev/null || echo "   pg_ctlcluster로 중지 시도 완료"
fi

# systemd 서비스 중지
echo "🛑 PostgreSQL 서비스 중지 중..."
sudo systemctl stop postgresql

# PostgreSQL 16 서비스가 별도로 있는 경우
if systemctl list-unit-files | grep -q "postgresql@16"; then
    echo "🛑 PostgreSQL 16 서비스 중지 중..."
    sudo systemctl stop postgresql@16-main 2>/dev/null || true
fi

# 잠시 대기
sleep 2

# 서버 상태 확인
echo ""
echo "📋 서버 상태 확인 중..."

# 프로세스 확인
if pgrep -x postgres > /dev/null; then
    echo "⚠️  PostgreSQL 프로세스가 아직 실행 중입니다"
    echo "   강제 종료를 시도합니다..."
    sudo pkill -9 postgres 2>/dev/null || true
    sleep 1
    if pgrep -x postgres > /dev/null; then
        echo "❌ PostgreSQL 프로세스를 완전히 종료하지 못했습니다"
    else
        echo "✅ PostgreSQL 프로세스 종료 완료"
    fi
else
    echo "✅ PostgreSQL 프로세스가 실행되지 않습니다"
fi

# 포트 리스닝 확인
if sudo ss -tlnp 2>/dev/null | grep -q ":5432" || netstat -tlnp 2>/dev/null | grep -q ":5432"; then
    echo "⚠️  포트 5432가 아직 리스닝 중입니다"
else
    echo "✅ 포트 5432가 리스닝되지 않습니다"
fi

echo ""
echo "=========================================="
echo "중지 완료!"
echo "=========================================="
echo ""
echo "💡 DB 서버를 다시 시작하려면: ./restart_db_server.sh"

