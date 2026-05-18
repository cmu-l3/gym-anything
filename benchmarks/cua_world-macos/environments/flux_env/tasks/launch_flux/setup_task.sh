#!/bin/bash
# Pre-task: launch f.lux and wait for it to register with LaunchServices.
# Idempotent — if Flux is already running, just wait for registration.
#
# f.lux is a menu-bar agent (LSUIElement=true); it does NOT open a window
# by default. The smoke check is therefore "process running AND bundle
# registered in lsappinfo", not "window appeared on screen".
set -eu

if ! pgrep -x "Flux" >/dev/null; then
  echo "[pre_task] launching f.lux"
  open -a Flux
fi

# Poll lsappinfo for the bundle path. Per the preview_env lesson in
# 12_macos_environments.md, helper-free apps like Flux don't match the
# safari-style `Flux( |$)` word-boundary regex (their lsappinfo entry is
# `"Flux" ASN:...` — followed by a quote, not a space or end of line).
# Match the bundle-path line `bundle path=".../Flux.app"` instead.
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'Flux\.app'; then
    echo "[pre_task] f.lux registered after ${i}s"
    break
  fi
  sleep 1
done

# Brief settle so the menu-bar icon lays out before any screenshot is taken.
sleep 2
