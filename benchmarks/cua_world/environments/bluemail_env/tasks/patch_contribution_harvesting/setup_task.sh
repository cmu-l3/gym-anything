#!/bin/bash
echo "=== Setting up patch_contribution_harvesting task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Reset Maildir to known state (50 ham emails)
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# clean existing
rm -rf "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Patch-Review" 2>/dev/null || true

# Remove other custom folders to ensure clean slate
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# Clear Drafts/Sent
rm -rf "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Load 50 ham emails
echo "Loading emails..."
TIMESTAMP=$(date +%s)
IDX=0
PATCH_COUNT_BASELINE=0

for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    # Check if this email looks like a patch (for ground truth baseline)
    if grep -qE "^diff -u|^Index:|^--- .*^\\+\\+\+ |\[PATCH\]" "$eml_file"; then
        PATCH_COUNT_BASELINE=$((PATCH_COUNT_BASELINE + 1))
    fi

    # Copy to inbox
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

echo "Loaded $IDX emails. Baseline patch count: $PATCH_COUNT_BASELINE"
echo "$PATCH_COUNT_BASELINE" > /tmp/baseline_patch_count.txt

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# Prepare Application
# ============================================================
# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize window
sleep 5
maximize_bluemail

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="