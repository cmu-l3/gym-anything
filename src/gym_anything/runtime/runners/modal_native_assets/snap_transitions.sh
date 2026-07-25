#!/bin/bash
set -euo pipefail

cache_dir=/var/lib/gym-anything/snap-transitions
manifest="$cache_dir/packages"

prepare() {
    install -d -m 0755 "$cache_dir"
    : > "$manifest"

    while IFS=$'\t' read -r status package summary; do
        summary=${summary,,}
        if [[ "$status" == ii* && "$summary" == *"transitional package"* && "$summary" == *snap* ]]; then
            printf '%s\n' "$package" >> "$manifest"
        fi
    done < <(
        dpkg-query -W -f='${db:Status-Abbrev}\t${binary:Package}\t${binary:Summary}\n'
    )

    sort -u -o "$manifest" "$manifest"
    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        (cd "$cache_dir" && apt-get download "$package")
    done < "$manifest"
}

replay() {
    if [[ -s "$manifest" ]]; then
        shopt -s nullglob
        packages=("$cache_dir"/*.deb)
        ((${#packages[@]} > 0)) || {
            echo "Snap transition manifest exists without cached Debian packages" >&2
            return 1
        }

        # These Ubuntu transition packages invoke snap(8) from their maintainer
        # scripts. Replaying them after snapd is live completes work that cannot
        # run while Modal constructs the image without systemd.
        DEBIAN_FRONTEND=noninteractive dpkg --unpack "${packages[@]}"
        DEBIAN_FRONTEND=noninteractive dpkg --configure -a
    fi

    /usr/local/sbin/ga-snap-mounts
    /usr/bin/snap refresh --hold=forever >/dev/null
}

case "${1:-replay}" in
    prepare)
        prepare
        ;;
    replay)
        replay
        ;;
    *)
        echo "usage: $0 [prepare|replay]" >&2
        exit 64
        ;;
esac
