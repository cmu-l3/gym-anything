#!/bin/bash
set -e
echo "=== Setting up cleanup_disk_space task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define target details
DOMAIN="acmecorp.test"
USER="acmecorp"
HOME_DIR="/home/${USER}"
TARGET_DIR="${HOME_DIR}/public_html/assets/media/temp"
TARGET_FILE="${TARGET_DIR}/render_temp_vfx_full_resolution.dat"

# Ensure the user exists (acmecorp.test is a pre-seeded domain)
if ! id "$USER" >/dev/null 2>&1; then
    echo "ERROR: User $USER does not exist. Environment may need restart."
    exit 1
fi

# Create deep directory structure
mkdir -p "$TARGET_DIR"

# Create a 200MB dummy file
echo "--- Creating 200MB target file ---"
# using /dev/urandom is too slow for 200MB in some envs, using /dev/zero is faster
# verification checks existence, not entropy
dd if=/dev/zero of="$TARGET_FILE" bs=1M count=200 status=none

# Set correct ownership so it counts towards quota
chown -R "${USER}:${USER}" "${HOME_DIR}/public_html/assets"
chmod 644 "$TARGET_FILE"

# Verify creation
if [ -f "$TARGET_FILE" ]; then
    SIZE=$(stat -c %s "$TARGET_FILE")
    echo "Target file created at $TARGET_FILE (Size: $SIZE bytes)"
    echo "$TARGET_FILE" > /tmp/target_file_path.txt
else
    echo "ERROR: Failed to create target file"
    exit 1
fi

# Force Virtualmin to re-check quotas/disk usage so the report is accurate immediately
echo "--- Refreshing Virtualmin disk usage ---"
virtualmin list-domains --domain "$DOMAIN" --quotas >/dev/null 2>&1 || true

# Ensure Virtualmin is ready in Firefox
ensure_virtualmin_ready

# Navigate to the domain summary page to start
# We want the agent to find "Disk Usage" themselves, so we just go to the domain
DOMAIN_ID=$(get_domain_id "$DOMAIN")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/edit_domain.cgi?dom=${DOMAIN_ID}"
else
    navigate_to "https://localhost:10000/virtual-server/index.cgi"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="