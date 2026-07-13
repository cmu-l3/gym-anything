#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l

echo "=== Weird CAPTCHA Gym: install shared runtime ==="

if ! command -v python3 >/dev/null 2>&1; then
  apt-get update -yq
  apt-get install -yq --no-install-recommends python3
fi

if command -v google-chrome-stable >/dev/null 2>&1 ||
   command -v google-chrome >/dev/null 2>&1 ||
   command -v chromium >/dev/null 2>&1 ||
   command -v chromium-browser >/dev/null 2>&1 ||
   command -v firefox >/dev/null 2>&1; then
  echo "Browser already available."
  exit 0
fi

echo "No browser found; attempting best-effort browser install."
apt-get update -yq || true
apt-get install -yq --no-install-recommends ca-certificates wget gnupg xdg-utils wmctrl || true

arch="$(uname -m)"
if [ "$arch" = "x86_64" ] || [ "$arch" = "amd64" ]; then
  if ! command -v google-chrome-stable >/dev/null 2>&1; then
    wget -q -O /tmp/google_linux_signing_key.pub https://dl.google.com/linux/linux_signing_key.pub || true
    if [ -s /tmp/google_linux_signing_key.pub ]; then
      gpg --dearmor < /tmp/google_linux_signing_key.pub > /usr/share/keyrings/google-linux.gpg || true
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
      apt-get update -yq || true
      apt-get install -yq --no-install-recommends google-chrome-stable || true
    fi
  fi
fi

if ! command -v google-chrome-stable >/dev/null 2>&1 &&
   ! command -v google-chrome >/dev/null 2>&1 &&
   ! command -v chromium >/dev/null 2>&1 &&
   ! command -v chromium-browser >/dev/null 2>&1 &&
   ! command -v firefox >/dev/null 2>&1; then
  apt-get install -yq --no-install-recommends firefox chromium-browser chromium || true
fi

echo "Runtime install complete. Browser command, if any:"
command -v google-chrome-stable || command -v google-chrome || command -v chromium || command -v chromium-browser || command -v firefox || true
