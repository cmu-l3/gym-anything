#!/bin/bash
# export_result.sh — Portal Compliance and Rebranding Audit

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/portal_compliance_result.json"
TMP_DB_RAW="/tmp/_portal_db_raw.txt"
TMP_HTML_LOGIN="/tmp/_portal_html_login.txt"
TMP_HTML_APP="/tmp/_portal_html_app.txt"

echo "[export] Exporting portal compliance data..."

# ------------------------------------------------------------
# 1. Fetch Login Page HTML
# ------------------------------------------------------------
echo "[export] Fetching login page HTML..."
curl -s -L "http://localhost:8060/apiclient/ember/Login.jsp" > "$TMP_HTML_LOGIN" || echo "FAIL" > "$TMP_HTML_LOGIN"
curl -s -L "http://localhost:8060/" > "$TMP_HTML_APP" || echo "FAIL" > "$TMP_HTML_APP"

# ------------------------------------------------------------
# 2. Query DB for Security and Rebranding Tables
# ------------------------------------------------------------
echo "[export] Querying DB for compliance and rebranding settings..."

{
    echo "=== REBRANDING & SYSTEM SETTINGS TABLES ==="
    REBRAND_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%rebrand%' OR tablename ILIKE '%custom%' OR tablename ILIKE '%global%' OR tablename ILIKE '%system%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
    
    for tbl in $REBRAND_TABLES; do
        if [ -n "$tbl" ]; then
            echo ""
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
        fi
    done

    echo ""
    echo "=== SECURITY & AAA TABLES ==="
    AAA_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%aaa%password%' OR tablename ILIKE '%aaa%account%' OR tablename ILIKE '%aaa%login%' OR tablename ILIKE '%aaa%policy%' OR tablename ILIKE '%secur%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

    for tbl in $AAA_TABLES; do
        if [ -n "$tbl" ]; then
            echo ""
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
        fi
    done

} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 3. Assemble JSON
# ------------------------------------------------------------
echo "[export] Assembling JSON..."

python3 << 'PYEOF'
import json

def read_file(path):
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read()
    except Exception:
        return ""

db_raw = read_file("/tmp/_portal_db_raw.txt")
html_login = read_file("/tmp/_portal_html_login.txt")
html_app = read_file("/tmp/_portal_html_app.txt")

result = {
    "db_raw": db_raw,
    "html_login": html_login,
    "html_app": html_app
}

with open("/tmp/portal_compliance_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/portal_compliance_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/portal_compliance_result_tmp.json" "$RESULT_FILE" 2>/dev/null || sudo mv "/tmp/portal_compliance_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

# Take final screenshot
take_screenshot "/tmp/portal_compliance_final_screenshot.png" || true

echo "[export] Done."