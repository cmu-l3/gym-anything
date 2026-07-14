#!/bin/bash
set -uo pipefail

real_snap=/usr/bin/snap
"$real_snap" "$@"
status=$?

if ((status == 0)); then
    command=
    for argument in "$@"; do
        if [[ "$argument" != -* ]]; then
            command=$argument
            break
        fi
    done

    case "$command" in
        install|refresh|revert|enable|disable|remove|try|switch|remodel)
            if ((EUID == 0)); then
                /usr/local/sbin/ga-snap-mounts || status=$?
            else
                sudo -n /usr/local/sbin/ga-snap-mounts || status=$?
            fi
            ;;
    esac
fi

exit "$status"
