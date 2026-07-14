#!/bin/bash
set -euo pipefail

pid_file=/run/gym-anything/systemd.pid
if [[ ! -s "$pid_file" ]]; then
    echo "Modal Native systemd namespace is not ready" >&2
    exit 70
fi

target_pid=$(<"$pid_file")
if [[ ! -d "/proc/$target_pid" ]]; then
    echo "Modal Native systemd namespace is no longer running" >&2
    exit 70
fi

exec /usr/bin/nsenter --target "$target_pid" --mount --pid -- "$@"
