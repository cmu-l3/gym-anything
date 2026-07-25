#!/bin/bash
set -euo pipefail

extracted_root=/var/lib/gym-anything/snap-extracted
lock_file=/run/lock/gym-anything-snap-mounts.lock
temporary_dir=

mapfile -t initial_pids < <(pgrep -x snapfuse || true)
((${#initial_pids[@]} > 0)) || exit 0

install -d -m 0755 "$extracted_root" /run/lock
exec 9>"$lock_file"
flock 9

# Another reconciler may have handled every mount while this process waited.
mapfile -t snapfuse_pids < <(pgrep -x snapfuse || true)
((${#snapfuse_pids[@]} > 0)) || exit 0

restart_snapd() {
    if [[ -n "$temporary_dir" ]]; then
        rm -rf -- "$temporary_dir"
    fi
    systemctl start snapd.socket snapd.service >/dev/null 2>&1 || true
}
trap restart_snapd EXIT

# snapd can execute from its own Snap, so stop it before replacing all FUSE
# mounts. The socket and daemon are restarted by the EXIT trap.
systemctl stop snapd.socket snapd.service >/dev/null 2>&1 || true

for pid in "${snapfuse_pids[@]}"; do
    cmdline="/proc/$pid/cmdline"
    [[ -r "$cmdline" ]] || continue
    mapfile -d '' -t argv < "$cmdline" || true
    source=${argv[1]:-}
    target=${argv[2]:-}

    [[ "$source" == /var/lib/snapd/snaps/*.snap ]] || continue
    [[ "$target" == /snap/*/* ]] || continue
    [[ -f "$source" && -d "$target" ]] || continue

    key=$(basename -- "$source" .snap)
    [[ "$key" =~ ^[A-Za-z0-9._+-]+$ ]] || {
        echo "Ignoring unsafe Snap filename: $source" >&2
        continue
    }

    destination="$extracted_root/$key"
    complete="$extracted_root/.$key.complete"
    if [[ ! -f "$complete" ]]; then
        rm -rf -- "$destination"
        temporary_dir=$(mktemp -d "$extracted_root/.$key.XXXXXX")
        unsquashfs -f -d "$temporary_dir" "$source" >/dev/null
        mv -- "$temporary_dir" "$destination"
        temporary_dir=
        touch "$complete"
    fi

    # The application may have been launched concurrently. Preserve its mount
    # rather than forcing a lazy unmount; the next boot/reconcile will retry.
    if ! umount "$target"; then
        echo "Could not replace busy Snap mount: $target" >&2
        continue
    fi
    mount --bind "$destination" "$target"
    mount -o remount,bind,ro,nodev "$target"
done
