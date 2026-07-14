#!/bin/bash
set -euo pipefail

geometry="${GYM_ANYTHING_VNC_GEOMETRY:-1920x1080}"
password="${GYM_ANYTHING_VNC_PASSWORD:-password}"

install -d -m 0755 /run/gym-anything /etc/gym-anything
install -d -o ga -g ga -m 0700 /home/ga/.vnc
printf '%s\n' "$password" | vncpasswd -f > /home/ga/.vnc/passwd
chown ga:ga /home/ga/.vnc/passwd
chmod 0600 /home/ga/.vnc/passwd
printf 'GA_VNC_GEOMETRY=%s\n' "$geometry" > /etc/gym-anything/vnc.env

rm -f /run/gym-anything/systemd.pid
/usr/bin/unshare --fork --pid --mount --mount-proc /usr/local/sbin/ga-systemd-init &
launcher_pid=$!

for _ in $(seq 1 300); do
    systemd_pid=$(pgrep -P "$launcher_pid" | head -n 1 || true)
    if [[ -n "$systemd_pid" && -d "/proc/$systemd_pid" ]]; then
        printf '%s\n' "$systemd_pid" > /run/gym-anything/systemd.pid
        break
    fi
    if ! kill -0 "$launcher_pid" 2>/dev/null; then
        wait "$launcher_pid"
        exit $?
    fi
    sleep 0.1
done

if [[ ! -s /run/gym-anything/systemd.pid ]]; then
    echo "systemd namespace child did not become visible" >&2
    exit 1
fi

wait "$launcher_pid"
