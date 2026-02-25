#!/bin/bash
# 네이버 클라우드 서버 자동 점검 스크립트 (Cron용)
# OS, MariaDB, PostgreSQL, Tomcat 점검을 순차적으로 실행
# --cron 옵션으로 실행 시 상세 로깅

set -e

# Cron 환경에서 PATH 제한됨 → ansible-playbook 등 명령어를 찾을 수 있도록 설정
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:$PATH"

# 로케일 설정 (Ansible 경고 방지)
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 로그 디렉토리 생성
mkdir -p "$SCRIPT_DIR/logs"

# 로그 파일 설정
LOG_DATE=$(date '+%Y%m%d')
LOG_FILE="$SCRIPT_DIR/logs/navercloud_check_${LOG_DATE}.log"

# 색상 코드 (터미널용)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# 로그 함수 (색상 코드 포함)
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 콘솔 출력 (색상 포함)
    echo -e "${BLUE}[${timestamp}] ${message}${NC}" | tee -a "$LOG_FILE"
}

# 성공 로그
log_success() {
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] ✅ ${message}${NC}" | tee -a "$LOG_FILE"
}

# 실패 로그
log_error() {
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] ❌ ${message}${NC}" | tee -a "$LOG_FILE"
}

# 경고 로그
log_warn() {
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] ⚠️  ${message}${NC}" | tee -a "$LOG_FILE"
}

# 점검 시작
START_TIME=$(date +%s)
CHECK_DATE=$(date '+%Y-%m-%d %H:%M:%S')

log "========================================="
log "네이버 클라우드 서버 자동 점검 시작"
log "점검 대상: nimbus-server (네이버 클라우드)"
log "점검 일시: ${CHECK_DATE}"
log "로그 파일: ${LOG_FILE}"
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 점검 결과 추적
TOTAL_CHECKS=0
OS_CHECK_RESULT=0
MARIADB_CHECK_RESULT=0
POSTGRESQL_CHECK_RESULT=0
TOMCAT_CHECK_RESULT=0

# 점검 실행 함수
run_check() {
    local check_name="$1"
    local check_command="$2"
    local check_id="$3"  # "os", "mariadb", "postgresql", "tomcat"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "${check_name} 점검 시작"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local check_start=$(date +%s)
    local exit_code=0
    
    # 점검 실행
    eval "$check_command" >> "$LOG_FILE" 2>&1 || exit_code=$?
    
    local check_end=$(date +%s)
    local check_duration=$((check_end - check_start))
    
    # 결과 저장
    case "$check_id" in
        "os") OS_CHECK_RESULT=$exit_code ;;
        "mariadb") MARIADB_CHECK_RESULT=$exit_code ;;
        "postgresql") POSTGRESQL_CHECK_RESULT=$exit_code ;;
        "tomcat") TOMCAT_CHECK_RESULT=$exit_code ;;
    esac
    
    if [ $exit_code -eq 0 ]; then
        log_success "${check_name} 점검 완료 (소요 시간: ${check_duration}초)"
    else
        log_error "${check_name} 점검 실패 (종료 코드: ${exit_code}, 소요 시간: ${check_duration}초)"
    fi
    
    log ""
}

# 서버에서 실행 시 hosts.ini.server 사용, 로컬에서는 hosts.ini 사용
if [ -f "hosts.ini.server" ]; then
    INVENTORY_FILE="hosts.ini.server"
    # 동국대 서버(dongguk_server1) 연결 가능 시에만 포함, 아니면 nimbus-server만 점검 (타임아웃 10초)
    if timeout 10 ansible dongguk_server1 -i hosts.ini.server -m ping -o >/dev/null 2>&1; then
        LIMIT_TARGET="nimbus-server,dongguk_server1"
        log "info" "동국대 서버 연결 가능 → nimbus-server + dongguk_server1 점검"
    else
        LIMIT_TARGET="nimbus-server"
        log "info" "동국대 서버 연결 불가 → nimbus-server만 점검"
    fi
else
    INVENTORY_FILE="hosts.ini"
    LIMIT_TARGET="nimbus-server"
fi

# 1. OS 점검
run_check "OS (Redhat)" "ansible-playbook -i ${INVENTORY_FILE} redhat_check/redhat_check.yml --limit ${LIMIT_TARGET}" "os"

# 2. MariaDB 점검
run_check "MariaDB" "ansible-playbook -i ${INVENTORY_FILE} mariadb_check/mariadb_check.yml --limit ${LIMIT_TARGET}" "mariadb"

# 3. PostgreSQL 점검
run_check "PostgreSQL" "ansible-playbook -i ${INVENTORY_FILE} postgresql_check/postgresql_check.yml --limit ${LIMIT_TARGET}" "postgresql"

# 4. Tomcat 점검
run_check "Tomcat" "ansible-playbook -i ${INVENTORY_FILE} tomcat_check/tomcat_check.yml --limit ${LIMIT_TARGET}" "tomcat"

# 점검 완료
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

log "========================================="
log "점검 결과 요약"
log "========================================="

# 각 점검 결과 요약
if [ $OS_CHECK_RESULT -eq 0 ]; then
    log_success "OS 점검: ✅ 성공"
else
    log_error "OS 점검: ❌ 실패"
fi

if [ $MARIADB_CHECK_RESULT -eq 0 ]; then
    log_success "MariaDB 점검: ✅ 성공"
else
    log_error "MariaDB 점검: ❌ 실패"
fi

if [ $POSTGRESQL_CHECK_RESULT -eq 0 ]; then
    log_success "PostgreSQL 점검: ✅ 성공"
else
    log_error "PostgreSQL 점검: ❌ 실패"
fi

if [ $TOMCAT_CHECK_RESULT -eq 0 ]; then
    log_success "Tomcat 점검: ✅ 성공"
else
    log_error "Tomcat 점검: ❌ 실패"
fi

# 성공/실패 카운트 계산
SUCCESS_COUNT=0
FAILED_COUNT=0
[ $OS_CHECK_RESULT -eq 0 ] && SUCCESS_COUNT=$((SUCCESS_COUNT + 1)) || FAILED_COUNT=$((FAILED_COUNT + 1))
[ $MARIADB_CHECK_RESULT -eq 0 ] && SUCCESS_COUNT=$((SUCCESS_COUNT + 1)) || FAILED_COUNT=$((FAILED_COUNT + 1))
[ $POSTGRESQL_CHECK_RESULT -eq 0 ] && SUCCESS_COUNT=$((SUCCESS_COUNT + 1)) || FAILED_COUNT=$((FAILED_COUNT + 1))
[ $TOMCAT_CHECK_RESULT -eq 0 ] && SUCCESS_COUNT=$((SUCCESS_COUNT + 1)) || FAILED_COUNT=$((FAILED_COUNT + 1))

log ""
log "총 점검 수: ${TOTAL_CHECKS}"
log "성공: ${SUCCESS_COUNT}"
log "실패: ${FAILED_COUNT}"
log "총 소요 시간: ${TOTAL_DURATION}초"

if [ $FAILED_COUNT -gt 0 ]; then
    log_warn "일부 점검이 실패했습니다. 로그를 확인하세요."
fi

log "로그 파일: ${LOG_FILE}"
log "========================================="

# 실패가 있으면 종료 코드 1 반환
if [ $FAILED_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi
