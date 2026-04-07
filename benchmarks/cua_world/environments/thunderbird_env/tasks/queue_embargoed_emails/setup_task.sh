#!/bin/bash
echo "=== Setting up Queue Embargoed Emails Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the PR Campaign directory
PR_DIR="/home/ga/Documents/PR_Campaign"
sudo -u ga mkdir -p "$PR_DIR"

# Generate real (minimal valid) PDF files using base64 so they are properly recognized as attachments
echo "Creating embargoed document files..."

# Document 1: exhibit_99_1_press_release.pdf
cat << 'EOF' | base64 -d > "$PR_DIR/exhibit_99_1_press_release.pdf"
JVBERi0xLjQKJcOkw7zDtsOfCjIgMCBvYmoKPDwvTGVuZ3RoIDMgMCBSL0ZpbHRlci9GbGF0ZURl
Y29kZT4+CnN0cmVhbQp4nDPQM1Qo5ypUMFAwALJMLU31jBQsTAz1LBSK0osSQ1KLivWcnPXTUvNK
ikpzdJwUXHNyIQKZRampRQpGhhYmhkbmxgYWagB/fA/5CmVuZHN0cmVhbQplbmRvYmoKCjMgMCBv
YmoKNjkKZW5kb2JqCgo0IDAgb2JqCjw8L1R5cGUvUGFnZS9NZWRpYUJveFswIDAgNTk1IDg0Ml0v
UmVzb3VyY2VzPDwvRm9udDw8L0YxIDEgMCBSPj4+Pi9Db250ZW50cyAyIDAgUi9QYXJlbnQgNSAw
IFI+PgplbmRvYmoKCjEgMCBvYmoKPDwvVHlwZS9Gb250L1N1YnR5cGUvVHlwZTEvQmFzZUZvbnQv
SGVsdmV0aWNhPj4KZW5kb2JqCgo1IDAgb2JqCjw8L1R5cGUvUGFnZXMvQ291bnQgMS9LaWRzWzQg
MCBSXT4+CmVuZG9iagoKNiAwIG9iago8PC9UeXBlL0NhdGFsb2cvUGFnZXMgNSAwIFI+PgplbmRv
YmoKCjcgMCBvYmoKPDwvUHJvZHVjZXIoR2hvc3RzY3JpcHQgOS41MCkvQ3JlYXRpb25EYXRlKEQ6
MjAyMTAxMDEwMDAwMDBaKT4+CmVuZG9iagoKeHJlZgowIDgKMDAwMDAwMDAwMCA2NTUzNSBmIAow
MDAwMDAwMjU4IDAwMDAwIG4gCjAwMDAwMDAwMTUgMDAwMDAgbiAKMDAwMDAwMDE1MyAwMDAwMCBu
IAowMDAwMDAwMTcyIDAwMDAwIG4gCjAwMDAwMDAzNDYgMDAwMDAgbiAKMDAwMDAwMDQwNSAwMDAw
MCBuIAowMDAwMDAwNDU0IDAwMDAwIG4gCnRyYWlsZXIKPDwvU2l6ZSA4L1Jvb3QgNiAwIFIvSW5m
byA3IDAgUj4+CnN0YXJ0eHJlZgo1NDkKJSVFT0YK
EOF

# Document 2: form_8k_current_report.pdf
cat << 'EOF' | base64 -d > "$PR_DIR/form_8k_current_report.pdf"
JVBERi0xLjQKJcOkw7zDtsOfCjIgMCBvYmoKPDwvTGVuZ3RoIDMgMCBSL0ZpbHRlci9GbGF0ZURl
Y29kZT4+CnN0cmVhbQp4nDPQM1Qo5ypUMFAwALJMLU31jBQsTAz1LBSK0osSQ1KLivWcnPXTUvNK
ikpzdJwUXHNyIQKZRampRQpGhhYmhkbmxgYWagB/fA/5CmVuZHN0cmVhbQplbmRvYmoKCjMgMCBv
YmoKNjkKZW5kb2JqCgo0IDAgb2JqCjw8L1R5cGUvUGFnZS9NZWRpYUJveFswIDAgNTk1IDg0Ml0v
UmVzb3VyY2VzPDwvRm9udDw8L0YxIDEgMCBSPj4+Pi9Db250ZW50cyAyIDAgUi9QYXJlbnQgNSAw
IFI+PgplbmRvYmoKCjEgMCBvYmoKPDwvVHlwZS9Gb250L1N1YnR5cGUvVHlwZTEvQmFzZUZvbnQv
SGVsdmV0aWNhPj4KZW5kb2JqCgo1IDAgb2JqCjw8L1R5cGUvUGFnZXMvQ291bnQgMS9LaWRzWzQg
MCBSXT4+CmVuZG9iagoKNiAwIG9iago8PC9UeXBlL0NhdGFsb2cvUGFnZXMgNSAwIFI+PgplbmRv
YmoKCjcgMCBvYmoKPDwvUHJvZHVjZXIoR2hvc3RzY3JpcHQgOS41MCkvQ3JlYXRpb25EYXRlKEQ6
MjAyMTAxMDEwMDAwMDBaKT4+CmVuZG9iagoKeHJlZgowIDgKMDAwMDAwMDAwMCA2NTUzNSBmIAow
MDAwMDAwMjU4IDAwMDAwIG4gCjAwMDAwMDAwMTUgMDAwMDAgbiAKMDAwMDAwMDE1MyAwMDAwMCBu
IAowMDAwMDAwMTcyIDAwMDAwIG4gCjAwMDAwMDAzNDYgMDAwMDAgbiAKMDAwMDAwMDQwNSAwMDAw
MCBuIAowMDAwMDAwNDU0IDAwMDAwIG4gCnRyYWlsZXIKPDwvU2l6ZSA4L1Jvb3QgNiAwIFIvSW5m
byA3IDAgUj4+CnN0YXJ0eHJlZgo1NDkKJSVFT0YK
EOF

chown -R ga:ga "$PR_DIR"

# Ensure Thunderbird is running
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30

# Maximize and focus the window
sleep 3
maximize_thunderbird
wid=$(get_thunderbird_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Close any accidentally open compose windows from previous states
su - ga -c "DISPLAY=:1 wmctrl -c 'Write:' 2>/dev/null" || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="