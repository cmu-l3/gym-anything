#!/bin/bash
set -eu

log_dir=${GA_LOG_DIR:-/tmp}
mkdir -p "$log_dir"

export DISPLAY="${DISPLAY:-:99}"
export XDG_RUNTIME_DIR=/tmp/runtime-ga
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
chown ga:ga "$XDG_RUNTIME_DIR" 2>/dev/null || true

export HOME_DIR=/workspace/home/ga
mkdir -p "$HOME_DIR"
chown ga:ga "$HOME_DIR" 2>/dev/null || true

cat <<'INNER' >/tmp/launch-gnome.sh
#!/bin/bash
set -u

HOME_ROOT="${HOME_DIR:-}"
if [ -z "$HOME_ROOT" ]; then
  HOME_ROOT="${HOME:-}"
fi
if [ -z "$HOME_ROOT" ]; then
  HOME_ROOT="/workspace/home/ga"
fi

export DISPLAY="${DISPLAY}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
export HOME="$HOME_ROOT"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
cd "$HOME_ROOT"

LOG_DIR="${GA_LOG_DIR:-/tmp}"
mkdir -p "$LOG_DIR"
log_msg() {
  echo "[start_gnome_inner] $1" >>"$LOG_DIR/start_gnome.log"
}

log_msg "launching GNOME session"
( gnome-session --session=gnome-flashback-metacity > "$LOG_DIR/gnome-session.log" 2>&1 ) &

for _ in $(seq 1 40); do
  if pgrep -u "$USER" -f gnome-session >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! pgrep -u "$USER" -f gnome-session >/dev/null 2>&1; then
  log_msg "GNOME session missing, starting openbox fallback"
  if command -v openbox-session >/dev/null 2>&1; then
    ( openbox-session > "$LOG_DIR/openbox.log" 2>&1 ) &
  else
    ( openbox > "$LOG_DIR/openbox.log" 2>&1 ) &
  fi
  sleep 3
fi

log_msg "launching gnome-text-editor"
( gnome-text-editor > "$LOG_DIR/gnome-text-editor.log" 2>&1 ) &

trap 'pkill -P $$ tail 2>/dev/null || true' EXIT

tail -f /dev/null &
wait $!
INNER
chmod +x /tmp/launch-gnome.sh

su - ga -c "DISPLAY=$DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR HOME=$HOME_DIR HOME_DIR=$HOME_DIR GA_LOG_DIR=$log_dir dbus-run-session -- /tmp/launch-gnome.sh" >>"$log_dir/start_gnome.log" 2>&1
