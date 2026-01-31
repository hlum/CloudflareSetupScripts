#!/usr/bin/env bash
set -e

SERVICE_NAME="cloudflared"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_DIR="/etc/cloudflared"
ENV_FILE="${ENV_DIR}/cloudflared.env"
CLOUDFLARED_BIN="$(command -v cloudflared || true)"

echo "======================================"
echo " Cloudflared セットアップツール"
echo " (systemctl / Tunnel Token 方式)"
echo "======================================"
echo
echo "モードを選択してください:"
echo " 1) 新規セットアップ（systemd サービス作成）"
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

  if systemctl list-units --full -all | grep -q "${SERVICE_NAME}.service"; then
    echo "🔄 サービスを再起動します..."
    sudo systemctl restart "$SERVICE_NAME"
  else
    echo "⚠️ サービスが存在しません（再起動はスキップ）"
  fi

  echo "✅ 完了"
  exit 0
fi

# MODE 1: new setup
echo
echo "⚙️ systemd サービスを作成中..."

sudo tee "$SERVICE_FILE" >/dev/null <<EOF
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

echo
echo "======================================"
echo "✅ セットアップ完了！"
echo
echo "確認コマンド:"
echo "  systemctl status cloudflared"
echo "======================================"