#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Transparent Database Encryption Result ==="

# Paths
VOLUME_PATH="/home/ga/Volumes/crm_encrypted.hc"
MOUNT_POINT="/home/ga/MountPoints/secure_store"
ORIGINAL_PATH="/home/ga/LegacyCRM/data/customers.db"

# 1. Check Volume Existence
VOLUME_EXISTS="false"
if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
fi

# 2. Check Mount Status
# Is the mount point actually a mount point?
MOUNT_ACTIVE="false"
if mountpoint -q "$MOUNT_POINT"; then
    MOUNT_ACTIVE="true"
fi

# 3. Check Symlink Status
IS_SYMLINK="false"
LINK_TARGET=""
if [ -L "$ORIGINAL_PATH" ]; then
    IS_SYMLINK="true"
    LINK_TARGET=$(readlink -f "$ORIGINAL_PATH")
fi

# 4. Check Database Accessibility via Symlink
DB_READABLE="false"
DB_WRITABLE="false"
RECORD_COUNT=0

if [ -e "$ORIGINAL_PATH" ]; then
    # Try reading
    if sqlite3 "$ORIGINAL_PATH" "SELECT COUNT(*) FROM customers;" > /tmp/db_count.txt 2>/dev/null; then
        DB_READABLE="true"
        RECORD_COUNT=$(cat /tmp/db_count.txt)
    fi
    
    # Try writing (integrity check)
    if sqlite3 "$ORIGINAL_PATH" "INSERT INTO customers (name, email) VALUES ('Test Verify', 'verify@test.com');" 2>/dev/null; then
        DB_WRITABLE="true"
    fi
fi

# 5. Verify File Location (Security Check)
# The file at ORIGINAL_PATH should resolve to inside MOUNT_POINT
RESOLVED_PATH=""
SECURE_LOCATION="false"
if [ "$IS_SYMLINK" = "true" ]; then
    RESOLVED_PATH=$(readlink -f "$ORIGINAL_PATH")
    if [[ "$RESOLVED_PATH" == "$MOUNT_POINT"* ]]; then
        SECURE_LOCATION="true"
    fi
fi

# 6. Check Encryption (via VeraCrypt CLI)
ENCRYPTION_ALGO="unknown"
if [ "$MOUNT_ACTIVE" = "true" ]; then
    # We can try to grep the volume info if we know the slot, but identifying slot is tricky.
    # Instead, we rely on the fact that if it's mounted at our mountpoint via VeraCrypt, it's encrypted.
    # We can list mounted volumes to confirm.
    VC_LIST=$(veracrypt --text --list --non-interactive 2>/dev/null)
    if echo "$VC_LIST" | grep -q "$MOUNT_POINT"; then
        ENCRYPTION_CONFIRMED="true"
    else
        ENCRYPTION_CONFIRMED="false"
    fi
else
    ENCRYPTION_CONFIRMED="false"
fi

# 7. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 8. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "mount_active": $MOUNT_ACTIVE,
    "is_symlink": $IS_SYMLINK,
    "link_target": "$LINK_TARGET",
    "db_readable": $DB_READABLE,
    "db_writable": $DB_WRITABLE,
    "record_count": $RECORD_COUNT,
    "secure_location": $SECURE_LOCATION,
    "encryption_confirmed": $ENCRYPTION_CONFIRMED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export completed. Result:"
cat /tmp/task_result.json