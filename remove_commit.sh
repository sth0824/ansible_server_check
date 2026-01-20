#!/bin/bash
# 특정 커밋 제거 스크립트

COMMIT_HASH="5954324a65e0855486c94c5dae9308728869d5be"

echo "🔍 커밋 정보 확인 중..."
git show $COMMIT_HASH --stat --oneline | head -20

echo ""
echo "⚠️  이 커밋을 제거하는 방법:"
echo "1. git revert (안전) - 커밋을 되돌리는 새 커밋 생성"
echo "2. git reset (위험) - 히스토리에서 완전히 제거"
echo ""
read -p "어떤 방법을 사용하시겠습니까? (1: revert, 2: reset) [1]: " choice
choice=${choice:-1}

if [ "$choice" = "1" ]; then
    echo "🔄 git revert 실행 중..."
    git revert $COMMIT_HASH --no-edit
    if [ $? -eq 0 ]; then
        echo "✅ 커밋이 되돌려졌습니다 (새 revert 커밋 생성됨)"
    else
        echo "❌ revert 실패 - 충돌이 발생했을 수 있습니다"
        exit 1
    fi
elif [ "$choice" = "2" ]; then
    echo "⚠️  WARNING: 이 작업은 히스토리를 변경합니다!"
    echo "   이미 푸시된 커밋이면 force push가 필요합니다"
    read -p "정말 진행하시겠습니까? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        # 커밋의 부모로 리셋
        git reset --hard $COMMIT_HASH^
        echo "✅ 커밋이 히스토리에서 제거되었습니다"
        echo "⚠️  원격 저장소에 푸시하려면: git push --force"
    else
        echo "취소되었습니다"
    fi
else
    echo "잘못된 선택입니다"
    exit 1
fi
