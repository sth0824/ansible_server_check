#!/bin/bash
# 로컬 PostgreSQL 데이터를 서버로 마이그레이션

set -e

# 서버 정보
SERVER_HOST="27.96.129.114"
SERVER_PORT="1025"
SSH_KEY="/home/sth0824/.ssh/nimso2026.pem"

# 로컬 DB 정보
LOCAL_DB="ansible_checks"
LOCAL_USER="ansible_user"
LOCAL_PASSWORD="nimbus1234"

# 서버 DB 정보
REMOTE_DB="ansible_checks"
REMOTE_USER="ansible_user"
REMOTE_PASSWORD="ansible_password_2024"

echo "=========================================="
echo "로컬 DB → 서버 DB 마이그레이션"
echo "=========================================="
echo ""

# 1. 로컬 DB 데이터 확인
echo "[1/4] 로컬 DB 데이터 확인..."
LOCAL_COUNT=$(PGPASSWORD=$LOCAL_PASSWORD psql -h localhost -U $LOCAL_USER -d $LOCAL_DB -t -c "SELECT COUNT(*) FROM check_results;" 2>/dev/null | tr -d ' ')

if [ -z "$LOCAL_COUNT" ] || [ "$LOCAL_COUNT" = "0" ]; then
    echo "⚠️  로컬 DB에 데이터가 없습니다 (또는 접속 실패)"
    echo "   계속 진행하시겠습니까? (y/n)"
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "✅ 로컬 DB 데이터: $LOCAL_COUNT 건"
fi
echo ""

# 2. 서버 DB 상태 확인
echo "[2/4] 서버 DB 상태 확인..."
REMOTE_COUNT=$(ssh -i "$SSH_KEY" -p "$SERVER_PORT" root@$SERVER_HOST \
    "sudo -u postgres psql -d $REMOTE_DB -t -c 'SELECT COUNT(*) FROM check_results;' 2>/dev/null" | tr -d ' ')

if [ -z "$REMOTE_COUNT" ]; then
    REMOTE_COUNT=0
fi

echo "서버 DB 데이터: $REMOTE_COUNT 건"

if [ "$REMOTE_COUNT" != "0" ]; then
    echo "⚠️  서버에 이미 데이터가 있습니다"
    echo "   덮어쓰시겠습니까? (y/n)"
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "마이그레이션 취소됨"
        exit 1
    fi
fi
echo ""

# 3. 데이터 덤프 (로컬)
echo "[3/4] 로컬 DB 데이터 덤프 중..."
DUMP_FILE="/tmp/ansible_checks_dump_$(date +%Y%m%d_%H%M%S).sql"

PGPASSWORD=$LOCAL_PASSWORD pg_dump -h localhost -U $LOCAL_USER -d $LOCAL_DB \
    --data-only \
    --table=check_results \
    --no-owner \
    --no-privileges \
    > "$DUMP_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "✅ 덤프 완료: $DUMP_FILE"
    DUMP_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
    echo "   크기: $DUMP_SIZE"
else
    echo "❌ 덤프 실패"
    exit 1
fi
echo ""

# 4. 서버로 전송 및 복원
echo "[4/4] 서버로 전송 및 복원 중..."
scp -i "$SSH_KEY" -P "$SERVER_PORT" "$DUMP_FILE" root@$SERVER_HOST:/tmp/ > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ 파일 전송 실패"
    exit 1
fi

REMOTE_DUMP="/tmp/$(basename $DUMP_FILE)"

ssh -i "$SSH_KEY" -p "$SERVER_PORT" root@$SERVER_HOST << EOF
    # 서버에서 데이터 복원
    export PGPASSWORD='$REMOTE_PASSWORD'
    psql -h localhost -U $REMOTE_USER -d $REMOTE_DB < $REMOTE_DUMP 2>&1
    
    # 복원 후 데이터 확인
    echo ""
    echo "=== 복원 후 데이터 확인 ==="
    sudo -u postgres psql -d $REMOTE_DB -c "SELECT COUNT(*) as total_records FROM check_results;"
    echo ""
    
    # 최근 데이터 확인
    sudo -u postgres psql -d $REMOTE_DB -c "SELECT id, check_type, hostname, check_time FROM check_results ORDER BY id DESC LIMIT 5;"
    
    # 임시 파일 삭제
    rm -f $REMOTE_DUMP
EOF

# 로컬 임시 파일 삭제
rm -f "$DUMP_FILE"

echo ""
echo "=========================================="
echo "마이그레이션 완료!"
echo "=========================================="
echo ""
echo "서버에서 데이터 확인:"
echo "  http://115.85.181.103:8000/api/dashboard"
echo ""
