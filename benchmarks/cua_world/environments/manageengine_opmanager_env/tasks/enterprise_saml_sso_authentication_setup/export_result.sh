#!/bin/bash
# export_result.sh — Enterprise SAML SSO Authentication Setup
# Queries the OpManager DB for SAML configurations and checks the conf directory
# for uploaded certificates, then writes /tmp/saml_sso_result.json.

set -euo pipefail
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/saml_sso_result.json"
TMP_DB_DUMP="/tmp/_saml_db_dump.txt"
TMP_FS_CHANGES="/tmp/_saml_fs_changes.txt"

# ------------------------------------------------------------
# 1. Query DB for SAML and Authentication tables
# ------------------------------------------------------------
echo "[export] Querying DB for SAML configurations..."

# Discover SAML/IdP/SSO related tables using opmanager_query()
ALL_SAML_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%saml%' OR tablename ILIKE '%idp%' OR tablename ILIKE '%sso%' OR tablename ILIKE '%auth%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Discovered candidate tables: $ALL_SAML_TABLES"

{
    echo "=== SAML/IDP DB TABLE DUMPS ==="
    echo "Candidate tables: $ALL_SAML_TABLES"
    echo ""

    if [ -n "$ALL_SAML_TABLES" ]; then
        for tbl in $ALL_SAML_TABLES; do
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 50;" 2>/dev/null || true
            echo ""
        done
    else
        echo "NO_SAML_TABLES_FOUND"
    fi
} > "$TMP_DB_DUMP" 2>&1

# ------------------------------------------------------------
# 2. Check File System for uploaded certificates/metadata
# ------------------------------------------------------------
echo "[export] Checking file system for uploaded certificates..."

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OPM_DIR=$(cat /tmp/opmanager_install_dir 2>/dev/null || echo "/opt/ManageEngine/OpManager")

{
    echo "=== RECENTLY MODIFIED FILES IN CONF DIR ==="
    if [ -d "$OPM_DIR/conf" ]; then
        # Find files modified since the task started that might be certificates or config
        find "$OPM_DIR/conf" -type f -newermt "@$TASK_START" -ls 2>/dev/null || true
        
        # Look specifically for SAML/IdP related files
        echo "=== ALL SAML/CERTIFICATE FILES IN CONF ==="
        find "$OPM_DIR/conf" -type f \( -iname "*saml*" -o -iname "*idp*" -o -iname "*.pem" -o -iname "*.crt" -o -iname "*.cer" \) -ls 2>/dev/null || true
    else
        echo "OPMANAGER_CONF_DIR_NOT_FOUND"
    fi
} > "$TMP_FS_CHANGES" 2>&1

# ------------------------------------------------------------
# 3. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception as e:
        return f"Error reading {path}: {e}"

db_dump = load_text("/tmp/_saml_db_dump.txt")
fs_changes = load_text("/tmp/_saml_fs_changes.txt")

result = {
    "saml_db_dump": db_dump,
    "saml_fs_changes": fs_changes
}

tmp_out = "/tmp/saml_sso_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Use safe_write_json if available, otherwise direct move
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/saml_sso_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/saml_sso_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_DB_DUMP" "$TMP_FS_CHANGES" "/tmp/saml_sso_result_tmp.json" || true