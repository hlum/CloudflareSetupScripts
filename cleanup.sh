#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="cloudflared"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="/etc/cloudflared/cloudflared.env"

echo "🧹 Cleaning up cloudflared..."

# 1️⃣ Stop service if running
if systemctl list-units --full -all | grep -q "${SERVICE_NAME}.service"; then
  echo "🛑 Stopping systemd service..."
  sudo systemctl stop "$SERVICE_NAME" || true
fi

# 2️⃣ Disable service if enabled
if systemctl list-unit-files | grep -q "${SERVICE_NAME}.service"; then
  echo "🚫 Disabling systemd service..."
  sudo systemctl disable "$SERVICE_NAME" || true
fi

# 3️⃣ Remove systemd service file
if [ -f "$SERVICE_FILE" ]; then
  echo "🗑 Removing systemd service file..."
  sudo rm -f "$SERVICE_FILE"
  sudo systemctl daemon-reload
fi

# 4️⃣ Kill any running cloudflared processes
if pgrep cloudflared >/dev/null; then
  echo "💀 Killing running cloudflared processes..."
  sudo pkill cloudflared || true
fi

# 5️⃣ Remove config directories
if [ -d "/etc/cloudflared" ]; then
  echo "🗑 Removing /etc/cloudflared..."
  sudo rm -rf /etc/cloudflared
fi

if [ -d "$HOME/.cloudflared" ]; then
  echo "🗑 Removing ~/.cloudflared..."
  rm -rf "$HOME/.cloudflared"
fi

if [ -d "/root/.cloudflared" ]; then
  echo "🗑 Removing /root/.cloudflared..."
  sudo rm -rf /root/.cloudflared
fi

# 6️⃣ Remove cloudflared binary
CLOUDFLARED_BIN="$(command -v cloudflared || true)"
if [ -n "$CLOUDFLARED_BIN" ]; then
  echo "🗑 Removing cloudflared binary: $CLOUDFLARED_BIN"
  sudo rm -f "$CLOUDFLARED_BIN"
fi

# 7️⃣ Final verification
echo "🔍 Final check..."
if pgrep cloudflared >/dev/null; then
  echo "⚠️ cloudflared still running!"
else
  echo "✅ cloudflared fully cleaned up"
fi