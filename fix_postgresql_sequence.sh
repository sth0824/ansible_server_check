#!/bin/bash
# PostgreSQL ID 시퀀스 생성 및 연결 스크립트
# 점검 결과 저장 문제 해결용

echo "🔧 PostgreSQL 시퀀스 생성 및 연결 중..."

# 서버 정보 (hosts.ini에서 확인한 정보)
SERVER_HOST="27.96.129.114"
SERVER_PORT="4433"
SSH_KEY="$HOME/.ssh/nimso2026.pem"
DB_USER="ansible_user"
DB_PASSWORD="nimbus1234"
DB_NAME="ansible_checks"

# SSH를 통해 PostgreSQL에 접속하여 시퀀스 생성
ssh -i "$SSH_KEY" -p "$SERVER_PORT" root@"$SERVER_HOST" bash << 'REMOTE_SCRIPT'
export PGPASSWORD='nimbus1234'
DB_USER="ansible_user"
DB_NAME="ansible_checks"

# 에러 발생 시 즉시 종료
set -e

# 1. 현재 최대 ID 확인
echo "📊 현재 최대 ID 확인 중..."
MAX_ID=$(psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COALESCE(MAX(id), 0) FROM check_results;" 2>&1 | grep -v "password\|Password" | tr -d ' ' | head -1)
if [ -z "$MAX_ID" ] || [ "$MAX_ID" = "" ]; then
    MAX_ID=0
fi
echo "📊 현재 최대 ID: $MAX_ID"

# 2. 다음 ID 계산 (최대 ID + 1)
NEXT_ID=$((MAX_ID + 1))
echo "📝 다음 ID: $NEXT_ID"

# 3. 시퀀스 생성 (이미 있으면 무시)
echo "🔧 시퀀스 생성 중..."
psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "CREATE SEQUENCE IF NOT EXISTS check_results_id_seq;" 2>&1 | grep -v "password\|Password" || true

# 4. 시퀀스를 id 컬럼에 연결 (기본값 설정)
echo "🔗 시퀀스를 id 컬럼에 연결 중..."
psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "ALTER TABLE check_results ALTER COLUMN id SET DEFAULT nextval('check_results_id_seq');" 2>&1 | grep -v "password\|Password" || true

# 5. 시퀀스의 현재 값을 다음 ID로 설정
echo "⚙️  시퀀스 값 설정 중..."
psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT setval('check_results_id_seq', $NEXT_ID);" 2>&1 | grep -v "password\|Password" || true

# 6. 시퀀스 확인
echo "✅ 시퀀스 생성 및 연결 완료!"
echo "   다음 ID는 $NEXT_ID부터 시작됩니다."

# 7. 시퀀스 존재 확인
SEQUENCE_EXISTS=$(psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT EXISTS(SELECT 1 FROM pg_sequences WHERE schemaname = 'public' AND sequencename = 'check_results_id_seq');" 2>&1 | grep -v "password\|Password" | tr -d ' ' | head -1)
if [ "$SEQUENCE_EXISTS" = "t" ]; then
    echo "✅ 시퀀스 확인: 존재함"
else
    echo "⚠️  시퀀스 확인: 존재하지 않음 (재시도 필요할 수 있음)"
fi
REMOTE_SCRIPT

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 시퀀스 설정 완료!"
    echo "   이제 점검 결과가 정상적으로 저장됩니다."
else
    echo ""
    echo "❌ 시퀀스 설정 실패"
    echo "   SSH 접속 및 PostgreSQL 연결을 확인하세요."
    exit 1
fi
