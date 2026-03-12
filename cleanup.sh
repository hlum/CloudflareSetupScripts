#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="cloudflared"
LAUNCHD_LABEL="com.cloudflare.cloudflared"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LAUNCHD_SERVICE_FILE="/Library/LaunchDaemons/${LAUNCHD_LABEL}.plist"
ENV_DIR="/etc/cloudflared"
ENV_FILE="${ENV_DIR}/cloudflared.env"
LOG_FILE="/var/log/cloudflared.log"
OS_TYPE="$(uname -s)"

echo "🧹 Cleaning up cloudflared..."

case "$OS_TYPE" in
  Linux)
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
    if [ -f "$SYSTEMD_SERVICE_FILE" ]; then
      echo "🗑 Removing systemd service file..."
      sudo rm -f "$SYSTEMD_SERVICE_FILE"
      sudo systemctl daemon-reload
    fi
    ;;
  Darwin)
    if [ -f "$LAUNCHD_SERVICE_FILE" ]; then
      echo "🛑 Unloading LaunchDaemon..."
      sudo launchctl bootout system "$LAUNCHD_SERVICE_FILE" >/dev/null 2>&1 || true

      echo "🚫 Disabling LaunchDaemon..."
      sudo launchctl disable "system/${LAUNCHD_LABEL}" >/dev/null 2>&1 || true

      echo "🗑 Removing LaunchDaemon plist..."
      sudo rm -f "$LAUNCHD_SERVICE_FILE"
    else
      sudo launchctl bootout "system/${LAUNCHD_LABEL}" >/dev/null 2>&1 || true
      sudo launchctl disable "system/${LAUNCHD_LABEL}" >/dev/null 2>&1 || true
    fi
    ;;
  *)
    echo "❌ Unsupported OS: ${OS_TYPE}"
    exit 1
    ;;
esac

# 4️⃣ Kill any running cloudflared processes
PIDS="$(pgrep -x cloudflared || true)"
if [ -n "$PIDS" ]; then
  echo "💀 Killing running cloudflared processes..."
  for pid in $PIDS; do
    sudo kill "$pid" || true
  done
fi

# 5️⃣ Remove config directories
if [ -d "$ENV_DIR" ]; then
  echo "🗑 Removing ${ENV_DIR}..."
  sudo rm -rf "$ENV_DIR"
fi

if [ -d "$HOME/.cloudflared" ]; then
  echo "🗑 Removing ~/.cloudflared..."
  rm -rf "$HOME/.cloudflared"
fi

if [ -d "/root/.cloudflared" ]; then
  echo "🗑 Removing /root/.cloudflared..."
  sudo rm -rf /root/.cloudflared
fi

if [ "$OS_TYPE" = "Darwin" ] && [ -f "$LOG_FILE" ]; then
  echo "🗑 Removing ${LOG_FILE}..."
  sudo rm -f "$LOG_FILE"
fi

# 6️⃣ Remove cloudflared binary
CLOUDFLARED_BIN="$(command -v cloudflared || true)"
if [ -n "$CLOUDFLARED_BIN" ]; then
  echo "🗑 Removing cloudflared binary: $CLOUDFLARED_BIN"
  sudo rm -f "$CLOUDFLARED_BIN"
fi

# 7️⃣ Final verification
echo "🔍 Final check..."
if pgrep -x cloudflared >/dev/null; then
  echo "⚠️ cloudflared still running!"
else
  echo "✅ cloudflared fully cleaned up"
fi
