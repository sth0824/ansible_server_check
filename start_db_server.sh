#!/bin/bash
# DB 서버 시작 스크립트 (기존 코드 방식 사용)
# setup_postgresql_remote_access.sh의 재시작 방식을 사용합니다

echo "=========================================="
echo "DB 서버 시작"
echo "=========================================="
echo ""

echo "5. PostgreSQL 시작..."
sudo systemctl restart postgresql

if [ $? -eq 0 ]; then
    echo "   ✅ PostgreSQL 재시작 완료"
else
    echo "   ❌ PostgreSQL 재시작 실패"
    echo "   설정 파일을 확인하세요."
    exit 1
fi

echo ""
echo "6. 설정 확인..."

# PostgreSQL 상태 확인
if sudo systemctl is-active --quiet postgresql; then
    echo "   ✅ PostgreSQL 실행 중"
else
    echo "   ❌ PostgreSQL이 실행되지 않습니다"
    exit 1
fi

# 포트 리스닝 확인
if sudo ss -tlnp | grep -q ":5432"; then
    echo "   ✅ 포트 5432 리스닝 중"
else
    echo "   ⚠️  포트 5432가 리스닝되지 않습니다"
fi

# 연결 테스트
echo ""
echo "🔍 데이터베이스 연결 테스트 중..."
if PGPASSWORD=nimbus1234 psql -h localhost -U ansible_user -d ansible_checks -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✅ 데이터베이스 연결 성공!"
    echo ""
    echo "📊 데이터베이스 정보:"
    echo "   호스트: localhost"
    echo "   포트: 5432"
    echo "   데이터베이스: ansible_checks"
    echo "   사용자: ansible_user"
else
    echo "⚠️  데이터베이스 연결 실패"
    echo "   잠시 후 다시 시도하거나 수동으로 확인하세요:"
    echo "   psql -h localhost -U ansible_user -d ansible_checks"
fi

echo ""
echo "=========================================="
echo "작업 완료!"
echo "=========================================="

