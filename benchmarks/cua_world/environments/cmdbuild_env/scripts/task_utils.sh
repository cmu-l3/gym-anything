#!/bin/bash

CMDBUILD_URL="http://localhost:8090/cmdbuild/ui/"

take_screenshot() {
  local output_file="${1:-/tmp/screenshot.png}"
  DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
  DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
  echo "WARNING: Could not capture screenshot" >&2
}

wait_for_rendered_browser_view() {
  local output_file="${1:-/tmp/task_start_screenshot.png}"
  local timeout="${2:-60}"
  local elapsed=0
  local probe="/tmp/task_start_probe.png"

  while [ "$elapsed" -lt "$timeout" ]; do
    take_screenshot "$probe"

    if [ -s "$probe" ]; then
      if command -v convert >/dev/null 2>&1; then
        local color_count
        color_count=$(convert "$probe" -crop 760x420+580+300 -colorspace Gray -format "%k" info: 2>/dev/null || echo "0")
        if [ "${color_count:-0}" -ge 20 ]; then
          cp "$probe" "$output_file"
          return 0
        fi
      else
        cp "$probe" "$output_file"
        return 0
      fi
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  [ -f "$probe" ] && cp "$probe" "$output_file" 2>/dev/null || true
  return 1
}

wait_for_window() {
  local pattern="$1"
  local timeout="${2:-30}"
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -Eqi "$pattern"; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

get_firefox_window_id() {
  DISPLAY=:1 wmctrl -l 2>/dev/null | grep -Ei "firefox|mozilla" | head -1 | awk '{print $1}'
}

focus_firefox() {
  local wid
  wid=$(get_firefox_window_id)
  if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    return 0
  fi
  return 1
}

wait_for_cmdbuild() {
  local timeout="${1:-180}"
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$CMDBUILD_URL" 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "302" ]; then
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  return 1
}

ensure_cmdbuild_running() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$CMDBUILD_URL" 2>/dev/null || echo "000")
  if [ "$code" = "200" ] || [ "$code" = "302" ]; then
    return 0
  fi

  echo "CMDBuild not responding, restarting Docker services..." >&2
  systemctl is-active docker || { systemctl start docker; sleep 5; }

  cd /home/ga/cmdbuild
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
  else
    docker compose up -d
  fi

  wait_for_cmdbuild 300
}

cmdbuild_query() {
  local query="$1"
  docker exec cmdbuild_db psql -U postgres -d cmdbuild_db4 -At -c "$query"
}

restart_firefox() {
  local url="${1:-$CMDBUILD_URL}"
  pkill -f firefox || true
  sleep 1
  su - ga -c "DISPLAY=:1 firefox '$url' > /tmp/firefox_task.log 2>&1 &"
  wait_for_window "firefox|mozilla|cmdbuild" 40
  focus_firefox || true
}

# Auto-check that CMDBuild is running when this file is sourced
ensure_cmdbuild_running
