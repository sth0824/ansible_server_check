#!/bin/bash
# Ansible 설치 스크립트
# 네이버 클라우드 서버에 Ansible 설치

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Ansible 설치 시작...${NC}"

# Python 확인
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3가 설치되어 있지 않습니다.${NC}"
    echo -e "${YELLOW}Python3 설치 중...${NC}"
    if command -v yum &> /dev/null; then
        yum install -y python3 python3-pip
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y python3 python3-pip
    else
        echo -e "${RED}❌ 패키지 매니저를 찾을 수 없습니다.${NC}"
        exit 1
    fi
fi

# pip 확인
if ! command -v pip3 &> /dev/null; then
    echo -e "${YELLOW}pip3 설치 중...${NC}"
    if command -v yum &> /dev/null; then
        yum install -y python3-pip
    elif command -v apt-get &> /dev/null; then
        apt-get install -y python3-pip
    fi
fi

# Ansible 확인
if command -v ansible-playbook &> /dev/null; then
    ANSIBLE_VERSION=$(ansible-playbook --version | head -1)
    echo -e "${GREEN}✅ Ansible이 이미 설치되어 있습니다: ${ANSIBLE_VERSION}${NC}"
    exit 0
fi

# Ansible 설치
echo -e "${YELLOW}Ansible 설치 중...${NC}"
pip3 install --upgrade pip
pip3 install ansible

# 설치 확인
if command -v ansible-playbook &> /dev/null; then
    ANSIBLE_VERSION=$(ansible-playbook --version | head -1)
    echo -e "${GREEN}✅ Ansible 설치 완료: ${ANSIBLE_VERSION}${NC}"
else
    echo -e "${RED}❌ Ansible 설치 실패${NC}"
    exit 1
fi
