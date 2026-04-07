#!/bin/bash
# Shared utilities for BlueMail environment tasks

# ============================================================
# Screenshot utilities
# ============================================================
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    local user="${2:-ga}"
    su - "$user" -c "DISPLAY=:1 scrot '$path'" 2>/dev/null || \
    su - "$user" -c "DISPLAY=:1 import -window root '$path'" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# ============================================================
# BlueMail process management
# ============================================================
BLUEMAIL_BINARY="/opt/BlueMail/bluemail"

is_bluemail_running() {
    pgrep -f "bluemail" > /dev/null 2>&1
}

get_bluemail_pid() {
    pgrep -f "bluemail" | head -1
}

start_bluemail() {
    if ! is_bluemail_running; then
        su - ga -c "DISPLAY=:1 /opt/BlueMail/bluemail --no-sandbox &" 2>/dev/null
        sleep 10  # Give BlueMail time to start
    fi
}

close_bluemail() {
    if is_bluemail_running; then
        # Try graceful close first
        su - ga -c "DISPLAY=:1 wmctrl -c 'BlueMail'" 2>/dev/null || true
        sleep 2
        # Force kill if still running
        if is_bluemail_running; then
            pkill -f "bluemail" 2>/dev/null || true
            sleep 1
        fi
    fi
}

maximize_bluemail() {
    local WID
    WID=$(su - ga -c "DISPLAY=:1 xdotool search --name 'BlueMail' 2>/dev/null" | head -1)
    if [ -n "$WID" ]; then
        su - ga -c "DISPLAY=:1 wmctrl -i -r '$WID' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    else
        # Try searching for bluemail window by class
        WID=$(su - ga -c "DISPLAY=:1 xdotool search --class 'bluemail' 2>/dev/null" | head -1)
        if [ -n "$WID" ]; then
            su - ga -c "DISPLAY=:1 wmctrl -i -r '$WID' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
        fi
    fi
}

wait_for_bluemail_window() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if su - ga -c "DISPLAY=:1 xdotool search --name 'BlueMail' 2>/dev/null" | head -1 | grep -q .; then
            echo "BlueMail window found"
            return 0
        fi
        # Also try searching by class name
        if su - ga -c "DISPLAY=:1 xdotool search --class 'bluemail' 2>/dev/null" | head -1 | grep -q .; then
            echo "BlueMail window found (by class)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "BlueMail window not found after ${timeout}s"
    return 1
}

# ============================================================
# Window detection utilities
# ============================================================
get_bluemail_windows() {
    su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -iE "(bluemail|blue mail)" || echo ""
}

get_any_window() {
    su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" || echo ""
}

# ============================================================
# Dovecot IMAP sync utilities
# ============================================================

# Force Dovecot to regenerate UIDVALIDITY so BlueMail discards its
# cached sync state and does a full re-sync of the mailbox.
# Call AFTER cleaning/repopulating Maildir and BEFORE restarting BlueMail.
reset_dovecot_indexes() {
    local MAILDIR="/home/ga/Maildir"
    echo "Resetting Dovecot indexes (UIDVALIDITY will change)..."
    rm -f "${MAILDIR}"/dovecot-uidvalidity* 2>/dev/null || true
    rm -f "${MAILDIR}"/dovecot.index* 2>/dev/null || true
    rm -f "${MAILDIR}"/dovecot-uidlist* 2>/dev/null || true
    rm -f "${MAILDIR}"/dovecot.list* 2>/dev/null || true
    # Also reset subfolder indexes
    for subdir in "${MAILDIR}"/.*/; do
        [ -d "$subdir" ] || continue
        rm -f "${subdir}"dovecot-uidvalidity* 2>/dev/null || true
        rm -f "${subdir}"dovecot.index* 2>/dev/null || true
        rm -f "${subdir}"dovecot-uidlist* 2>/dev/null || true
    done
    doveadm force-resync -u ga '*' 2>/dev/null || true
    echo "Dovecot indexes reset."
}

# ============================================================
# Email data utilities
# ============================================================
IMPORT_DIR="/home/ga/Mail/import"
SPAM_IMPORT_DIR="/home/ga/Mail/spam_import"

count_import_emails() {
    local dir="${1:-$IMPORT_DIR}"
    ls -1 "$dir" 2>/dev/null | wc -l
}

list_email_subjects() {
    local dir="${1:-$IMPORT_DIR}"
    for eml_file in "$dir"/*; do
        if [ -f "$eml_file" ]; then
            grep -m1 "^Subject:" "$eml_file" 2>/dev/null | sed 's/^Subject:\s*//' || echo "(no subject)"
        fi
    done
}
