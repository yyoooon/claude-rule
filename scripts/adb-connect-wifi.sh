#!/bin/sh
# Connect to Android device over Wi-Fi.
# Strategy:
#   1. If a Wi-Fi device (<IP>:5555) is already connected → done.
#   2. If only USB device → query its IP, switch to tcpip 5555, connect.
#   3. Otherwise → report no device.
# Prints a single status line to stdout (consumed by UserPromptSubmit hook).

set -e

DEVICES=$(adb devices 2>/dev/null | tail -n +2 | grep -v '^$' || true)

WIFI=$(echo "$DEVICES" | awk '$2=="device" && $1 ~ /:[0-9]+$/ {print $1; exit}')
if [ -n "$WIFI" ]; then
  echo "이미 Wi-Fi 연결됨: $WIFI"
  exit 0
fi

USB=$(echo "$DEVICES" | awk '$2=="device" && $1 !~ /:/ {print $1; exit}')
if [ -z "$USB" ]; then
  echo "디바이스 없음 (USB 연결 필요)"
  exit 0
fi

IP=$(adb -s "$USB" shell ip -f inet addr show wlan0 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}')
if [ -z "$IP" ]; then
  echo "디바이스 IP 조회 실패 (Wi-Fi 비활성?)"
  exit 0
fi

adb -s "$USB" tcpip 5555 >/dev/null 2>&1 || true
sleep 2
adb connect "$IP:5555" 2>&1
