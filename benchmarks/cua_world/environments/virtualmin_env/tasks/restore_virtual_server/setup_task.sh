#!/bin/bash
echo "=== Setting up restore_virtual_server task ==="
set -e

# Source utilities
source /workspace/scripts/task_utils.sh

# Configuration
DOMAIN="greenleaf-organics.test"
PASS="GreenLeaf2024!"
BACKUP_DIR="/home/ga/backups"
BACKUP_FILE="$BACKUP_DIR/greenleaf-organics-backup.tar.gz"
MARKER_CONTENT="Restoration Proof $(date +%s)"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"
chown ga:ga "$BACKUP_DIR"

# 1. Create the domain if it doesn't exist (to generate the backup)
if ! virtualmin_domain_exists "$DOMAIN"; then
    echo "Creating temp domain $DOMAIN for backup generation..."
    virtualmin create-domain \
        --domain "$DOMAIN" \
        --pass "$PASS" \
        --unix --dir --webmin --web --dns --mail --mysql \
        --default-features
fi

# 2. Add some "real" data to prove restoration works
echo "Adding content to $DOMAIN..."
# Add a marker file
su - "greenleaf-organics" -c "echo '$MARKER_CONTENT' > /home/greenleaf-organics/public_html/restore_proof.txt" 2>/dev/null || true

# Add an email user
if ! virtualmin list-users --domain "$DOMAIN" | grep -q "info@$DOMAIN"; then
    virtualmin create-user --domain "$DOMAIN" --user "info" --pass "InfoPass123" --real "Info User"
fi

# 3. Create the backup
echo "Creating backup at $BACKUP_FILE..."
virtualmin backup-domain \
    --dest "$BACKUP_FILE" \
    --domain "$DOMAIN" \
    --all-features \
    --newformat \
    --as-owner

chown ga:ga "$BACKUP_FILE"
echo "Backup created successfully."

# 4. Delete the domain (The Problem State)
echo "Simulating accidental deletion..."
virtualmin delete-domain --domain "$DOMAIN" --yes
echo "Domain $DOMAIN deleted."

# 5. Record state for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$MARKER_CONTENT" > /tmp/expected_marker.txt

# 6. Prepare GUI
ensure_virtualmin_ready

# Navigate to Backup and Restore page to save agent some clicks (optional, but helpful for "medium" difficulty)
# Or just go to dashboard
navigate_to "https://localhost:10000/virtual-server/"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Target: $DOMAIN"
echo "Backup: $BACKUP_FILE"