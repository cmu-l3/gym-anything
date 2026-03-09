#!/bin/bash
echo "=== Exporting connect_legacy_archive results ==="

source /workspace/scripts/task_utils.sh

# ==============================================================================
# GATHER EVIDENCE
# ==============================================================================

# 1. Determine expected file paths
DB_EXT=$(cat /tmp/expected_db_ext.txt 2>/dev/null || echo ".mdb")
ARCHIVE_BASE="/home/ga/Documents/visitor_archive_2024"
ARCHIVE_FILE="${ARCHIVE_BASE}${DB_EXT}"

# 2. Check for Lock File (Strongest evidence of active connection)
# Access uses .ldb or .laccdb; SQL CE uses .slock or file locking
LOCK_FILE_EXISTS="false"
LOCK_FILE_PATH=""

if [ -f "${ARCHIVE_BASE}.ldb" ]; then
    LOCK_FILE_EXISTS="true"
    LOCK_FILE_PATH="${ARCHIVE_BASE}.ldb"
elif [ -f "${ARCHIVE_BASE}.laccdb" ]; then
    LOCK_FILE_EXISTS="true"
    LOCK_FILE_PATH="${ARCHIVE_BASE}.laccdb"
elif [ -f "${ARCHIVE_BASE}.slock" ]; then
    LOCK_FILE_EXISTS="true"
    LOCK_FILE_PATH="${ARCHIVE_BASE}.slock"
fi

# 3. Check Wine Registry for Connection String / DB Path
# We search for the archive filename in the Jolly Technologies registry keys
echo "Querying registry..."
REG_DUMP_FILE="/tmp/registry_dump.txt"
su - ga -c "WINEDEBUG=-all wine reg query 'HKCU\\Software\\Jolly Technologies' /s" > "$REG_DUMP_FILE" 2>/dev/null || true

REGISTRY_UPDATED="false"
if grep -qi "visitor_archive_2024" "$REG_DUMP_FILE"; then
    REGISTRY_UPDATED="true"
    echo "Found archive path in registry."
fi

# 4. Check if App is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Capture final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# EXPORT JSON
# ==============================================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "lock_file_exists": $LOCK_FILE_EXISTS,
    "lock_file_path": "$LOCK_FILE_PATH",
    "registry_updated": $REGISTRY_UPDATED,
    "app_running": $APP_RUNNING,
    "archive_db_path": "$ARCHIVE_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="