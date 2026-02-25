#!/bin/bash
# 네이버 클라우드 서버 점검 실행 스크립트
# OS, MariaDB, PostgreSQL, Tomcat 점검을 순차적으로 실행

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 색상 출력
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}네이버 클라우드 서버 점검 시작${NC}"
echo -e "${BLUE}시작 시간: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. OS 점검
echo -e "${YELLOW}[1/4] OS 점검 실행 중...${NC}"
if ansible-playbook -i hosts.ini redhat_check/redhat_check.yml --limit nimbus-server; then
    echo -e "${GREEN}✅ OS 점검 완료${NC}"
else
    echo -e "${RED}❌ OS 점검 실패${NC}"
fi
echo ""

# 2. MariaDB 점검
echo -e "${YELLOW}[2/4] MariaDB 점검 실행 중...${NC}"
if ansible-playbook -i hosts.ini mariadb_check/mariadb_check.yml; then
    echo -e "${GREEN}✅ MariaDB 점검 완료${NC}"
else
    echo -e "${RED}❌ MariaDB 점검 실패${NC}"
fi
echo ""

# 3. PostgreSQL 점검
echo -e "${YELLOW}[3/4] PostgreSQL 점검 실행 중...${NC}"
if ansible-playbook -i hosts.ini postgresql_check/postgresql_check.yml; then
    echo -e "${GREEN}✅ PostgreSQL 점검 완료${NC}"
else
    echo -e "${RED}❌ PostgreSQL 점검 실패${NC}"
fi
echo ""

# 4. Tomcat 점검
echo -e "${YELLOW}[4/4] Tomcat 점검 실행 중...${NC}"
if ansible-playbook -i hosts.ini tomcat_check/tomcat_check.yml --limit nimbus-server; then
    echo -e "${GREEN}✅ Tomcat 점검 완료${NC}"
else
    echo -e "${RED}❌ Tomcat 점검 실패${NC}"
fi
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}점검 완료${NC}"
echo -e "${BLUE}종료 시간: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BLUE}========================================${NC}"
