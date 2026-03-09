#!/bin/bash
set -e
echo "=== Setting up task: restore_single_file_from_backup@1 ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Verify Virtualmin is ready & Firefox is open
ensure_virtualmin_ready

# 2. Ensure acmecorp.test exists
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass "GymAnything123!" --unix --dir --web --dns
fi

# Define paths
USER_HOME="/home/acmecorp"
WEB_DIR="$USER_HOME/public_html"
BACKUP_DIR="/home/ga/backups"

mkdir -p "$BACKUP_DIR"
chown ga:ga "$BACKUP_DIR"

echo "--- Preparing files for backup state ---"

# 3. Create the "Original" state (to be backed up)
# Create a dummy PDF using ImageMagick
if command -v convert >/dev/null; then
    convert -size 600x800 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 50,50 'Acme Corp Pricing 2024'" "$WEB_DIR/pricing.pdf"
else
    # Fallback if ImageMagick not present
    echo "%PDF-1.4 ... Acme Corp Pricing 2024 ..." > "$WEB_DIR/pricing.pdf"
fi
chown acmecorp:acmecorp "$WEB_DIR/pricing.pdf"

# Create the "Old" index.html (the one inside the backup)
echo "<html><body><h1>Acme Corp - OLD VERSION (Backup)</h1></body></html>" > "$WEB_DIR/index.html"
chown acmecorp:acmecorp "$WEB_DIR/index.html"

# Save checksum of the PDF (Target to restore)
PDF_MD5=$(md5sum "$WEB_DIR/pricing.pdf" | awk '{print $1}')
# Save checksum of the OLD index (The one we DON'T want at the end)
OLD_INDEX_MD5=$(md5sum "$WEB_DIR/index.html" | awk '{print $1}')

echo "--- Creating Backup ---"
# Create backup of the home directory feature only
virtualmin backup-domain --dest "$BACKUP_DIR/acmecorp_backup.tar.gz" \
                         --domain acmecorp.test \
                         --feature dir \
                         --as-owner

chown ga:ga "$BACKUP_DIR/acmecorp_backup.tar.gz"
echo "Backup created at $BACKUP_DIR/acmecorp_backup.tar.gz"

echo "--- Creating Post-Backup State (The 'Mess') ---"

# 4. Delete the target file (Simulate data loss)
rm "$WEB_DIR/pricing.pdf"

# 5. Update the protected file (Simulate recent work)
echo "<html><body><h1>Acme Corp - NEW UPDATED VERSION</h1><p>Recent changes that must be preserved!</p></body></html>" > "$WEB_DIR/index.html"
chown acmecorp:acmecorp "$WEB_DIR/index.html"

# Save checksum of the NEW index (The one we MUST keep)
NEW_INDEX_MD5=$(md5sum "$WEB_DIR/index.html" | awk '{print $1}')

# 6. Save ground truth hashes for export script and verifier
cat > /home/ga/.ground_truth_hashes.json <<EOF
{
    "pdf_original_md5": "$PDF_MD5",
    "index_old_md5": "$OLD_INDEX_MD5",
    "index_new_md5": "$NEW_INDEX_MD5"
}
EOF
chmod 644 /home/ga/.ground_truth_hashes.json

# 7. Record task start time
date +%s > /tmp/task_start_time.txt

# 8. Navigate browser to "Restore Backup" page to be helpful
# Virtualmin 8.x URL structure usually involves module name
# We'll just go to the domain summary page to let the agent find it
navigate_to "https://localhost:10000/virtual-server/"

# 9. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="