#!/bin/bash
# systemd 서비스로 설치 (백그라운드 실행)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "🔧 systemd 서비스 설치 중..."
echo ""

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "develop")

# 브랜치별 포트 설정
if [ "$CURRENT_BRANCH" = "UI_sunmin" ]; then
    PORT=8001
    SERVICE_NAME="ansible-api-ui-sunmin"
elif [ "$CURRENT_BRANCH" = "develop" ]; then
    PORT=8000
    SERVICE_NAME="ansible-api-develop"
else
    PORT=8000
    SERVICE_NAME="ansible-api-default"
fi

echo "🌿 현재 브랜치: $CURRENT_BRANCH"
echo "🔌 사용 포트: $PORT"
echo "📋 서비스 이름: $SERVICE_NAME"
echo ""

# 서비스 파일 생성
SERVICE_FILE="/tmp/${SERVICE_NAME}.service"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Ansible API Server ($CURRENT_BRANCH branch - Port $PORT)
After=network.target postgresql.service

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$SCRIPT_DIR/api_server
Environment="API_PORT=$PORT"
Environment="PATH=$SCRIPT_DIR/api_server/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$SCRIPT_DIR/api_server/venv/bin/python3 $SCRIPT_DIR/api_server/main.py
Restart=always
RestartSec=10
StandardOutput=append:$SCRIPT_DIR/api_server.log
StandardError=append:$SCRIPT_DIR/api_server.log

[Install]
WantedBy=multi-user.target
EOF

echo "📝 서비스 파일 생성 완료: $SERVICE_FILE"
echo ""

# 서비스 설치
echo "📦 서비스 설치 중..."
sudo cp "$SERVICE_FILE" "/etc/systemd/system/${SERVICE_NAME}.service"
sudo systemctl daemon-reload

echo "✅ 서비스 설치 완료!"
echo ""
echo "📋 사용 방법:"
echo "   시작: sudo systemctl start $SERVICE_NAME"
echo "   중지: sudo systemctl stop $SERVICE_NAME"
echo "   재시작: sudo systemctl restart $SERVICE_NAME"
echo "   상태 확인: sudo systemctl status $SERVICE_NAME"
echo "   자동 시작: sudo systemctl enable $SERVICE_NAME"
echo "   로그 확인: sudo journalctl -u $SERVICE_NAME -f"
