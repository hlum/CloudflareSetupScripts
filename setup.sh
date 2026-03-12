#!/usr/bin/env bash
set -e

SERVICE_NAME="cloudflared"
LAUNCHD_LABEL="com.cloudflare.cloudflared"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LAUNCHD_SERVICE_FILE="/Library/LaunchDaemons/${LAUNCHD_LABEL}.plist"
ENV_DIR="/etc/cloudflared"
ENV_FILE="${ENV_DIR}/cloudflared.env"
RUN_SCRIPT="${ENV_DIR}/run-cloudflared.sh"
CLOUDFLARED_BIN="$(command -v cloudflared || true)"
OS_TYPE="$(uname -s)"

echo "======================================"
echo " Cloudflared セットアップツール"
echo " (systemctl / launchctl / Tunnel Token 方式)"
echo "======================================"
echo
echo "モードを選択してください:"
echo " 1) 新規セットアップ（サービス作成）"
echo " 2) トークンのみ変更"
echo " 3) 終了"
echo
read -rp "番号を入力してください [1-3]: " MODE

if [[ "$MODE" == "3" ]]; then
  echo "終了します 👋"
  exit 0
fi

if [[ "$MODE" != "1" && "$MODE" != "2" ]]; then
  echo "❌ 無効な選択です"
  exit 1
fi

case "$OS_TYPE" in
  Linux|Darwin)
    ;;
  *)
    echo "❌ 未対応のOSです: ${OS_TYPE}"
    echo "Linux または macOS で実行してください"
    exit 1
    ;;
esac

# cloudflared binary check
if [[ -z "$CLOUDFLARED_BIN" ]]; then
  echo "❌ cloudflared がインストールされていません"
  echo "先に cloudflared をインストールしてください"
  exit 1
fi

# ask token
echo
read -rp "Tunnel Token を入力してください: " TUNNEL_TOKEN

if [[ -z "$TUNNEL_TOKEN" ]]; then
  echo "❌ Token が空です"
  exit 1
fi

echo
echo "📁 設定ディレクトリを作成中..."
sudo mkdir -p "$ENV_DIR"
sudo chmod 700 "$ENV_DIR"

echo "🔐 Token を保存中..."
sudo tee "$ENV_FILE" >/dev/null <<EOF
TUNNEL_TOKEN=${TUNNEL_TOKEN}
EOF
sudo chmod 600 "$ENV_FILE"

if [[ "$MODE" == "2" ]]; then
  echo "🔁 トークンのみ変更しました"

  case "$OS_TYPE" in
    Linux)
      if systemctl list-units --full -all | grep -q "${SERVICE_NAME}.service"; then
        echo "🔄 systemd サービスを再起動します..."
        sudo systemctl restart "$SERVICE_NAME"
      else
        echo "⚠️ systemd サービスが存在しません（再起動はスキップ）"
      fi
      ;;
    Darwin)
      if [[ -f "$LAUNCHD_SERVICE_FILE" ]]; then
        echo "🔄 LaunchDaemon を再起動します..."
        sudo launchctl bootout system "$LAUNCHD_SERVICE_FILE" >/dev/null 2>&1 || true
        sudo launchctl bootstrap system "$LAUNCHD_SERVICE_FILE"
        sudo launchctl enable "system/${LAUNCHD_LABEL}"
        sudo launchctl kickstart -k "system/${LAUNCHD_LABEL}"
      else
        echo "⚠️ LaunchDaemon が存在しません（再起動はスキップ）"
      fi
      ;;
  esac

  echo "✅ 完了"
  exit 0
fi

# MODE 1: new setup
echo
case "$OS_TYPE" in
  Linux)
    echo "⚙️ systemd サービスを作成中..."

    sudo tee "$SYSTEMD_SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
ExecStart=${CLOUDFLARED_BIN} tunnel run --token \${TUNNEL_TOKEN}
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    echo "🔄 systemd をリロード中..."
    sudo systemctl daemon-reload

    echo "🚀 サービスを有効化・起動中..."
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl restart "$SERVICE_NAME"
    ;;
  Darwin)
    echo "⚙️ LaunchDaemon を作成中..."

    sudo tee "$RUN_SCRIPT" >/dev/null <<EOF
#!/bin/sh
set -eu
. "${ENV_FILE}"
exec "${CLOUDFLARED_BIN}" tunnel run --token "\${TUNNEL_TOKEN}"
EOF
    sudo chmod 700 "$RUN_SCRIPT"

    sudo tee "$LAUNCHD_SERVICE_FILE" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHD_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${RUN_SCRIPT}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${ENV_DIR}</string>
  <key>StandardOutPath</key>
  <string>/var/log/cloudflared.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/cloudflared.log</string>
</dict>
</plist>
EOF
    sudo chown root:wheel "$LAUNCHD_SERVICE_FILE"
    sudo chmod 644 "$LAUNCHD_SERVICE_FILE"

    echo "🚀 LaunchDaemon を有効化・起動中..."
    sudo launchctl bootout system "$LAUNCHD_SERVICE_FILE" >/dev/null 2>&1 || true
    sudo launchctl bootstrap system "$LAUNCHD_SERVICE_FILE"
    sudo launchctl enable "system/${LAUNCHD_LABEL}"
    sudo launchctl kickstart -k "system/${LAUNCHD_LABEL}"
    ;;
esac

echo
echo "======================================"
echo "✅ セットアップ完了！"
echo
echo "確認コマンド:"
case "$OS_TYPE" in
  Linux)
    echo "  systemctl status cloudflared"
    ;;
  Darwin)
    echo "  sudo launchctl print system/${LAUNCHD_LABEL}"
    ;;
esac
echo "======================================"
