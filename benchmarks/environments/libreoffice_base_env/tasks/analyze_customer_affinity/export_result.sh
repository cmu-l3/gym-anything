#!/bin/bash
set -e
echo "=== Exporting analyze_customer_affinity results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Check if App is running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# 3. Check ODB file status
ODB_PATH="/home/ga/chinook.odb"
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE=0

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$ODB_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 4. Run internal Python script to inspect the ODB content and verify logic
# This script extracts the SQL from the ODB and compares it against the SQLite ground truth
cat > /tmp/inspect_odb.py << 'EOF'
import zipfile
import xml.etree.ElementTree as ET
import sqlite3
import json
import sys
import os
import re

ODB_PATH = "/home/ga/chinook.odb"
SQLITE_PATH = "/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite"
QUERY_NAME = "DeepCatalogCustomers"

result = {
    "query_found": False,
    "extracted_sql": None,
    "sql_structure_valid": False,
    "execution_success": False,
    "row_count": 0,
    "ground_truth_row_count": 0,
    "results_match": False,
    "error": None
}

def normalize_sql(sql):
    """Normalize SQL for basic comparison."""
    if not sql: return ""
    return ' '.join(sql.replace('\n', ' ').split()).lower()

try:
    if not os.path.exists(ODB_PATH):
        raise FileNotFoundError("ODB file not found")

    # 1. Extract SQL from ODB (content.xml)
    with zipfile.ZipFile(ODB_PATH, 'r') as z:
        with z.open('content.xml') as f:
            tree = ET.parse(f)
            root = tree.getroot()
            
            # Namespaces in ODB content.xml
            ns = {
                'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                'xlink': 'http://www.w3.org/1999/xlink'
            }
            
            # Find the query definition
            # Path: office:body -> office:database -> db:queries -> db:query
            for query in root.findall(".//db:query", ns):
                name = query.get(f"{{{ns['db']}}}name")
                if name == QUERY_NAME:
                    result["query_found"] = True
                    result["extracted_sql"] = query.get(f"{{{ns['db']}}}command")
                    break

    # 2. Analyze SQL Structure (Static Analysis)
    if result["query_found"] and result["extracted_sql"]:
        sql = result["extracted_sql"]
        norm_sql = normalize_sql(sql)
        
        # Check for required keywords/clauses
        has_join = "join" in norm_sql
        has_group = "group by" in norm_sql
        has_having = "having" in norm_sql
        has_count = "count" in norm_sql
        has_distinct = "distinct" in norm_sql
        excludes_artist = "various artists" in norm_sql.replace("'", "").replace('"', "")
        
        result["sql_structure_valid"] = all([has_join, has_group, has_having, has_count, excludes_artist])

    # 3. Ground Truth Verification (using SQLite)
    # We construct the correct query and run it against the reference SQLite DB
    if os.path.exists(SQLITE_PATH):
        conn = sqlite3.connect(SQLITE_PATH)
        cursor = conn.cursor()
        
        # Ground Truth Query
        gt_sql = """
            SELECT 
                c.FirstName || ' ' || c.LastName as CustomerName,
                ar.Name as ArtistName,
                COUNT(DISTINCT t.AlbumId) as AlbumCount
            FROM Customer c
            JOIN Invoice i ON c.CustomerId = i.CustomerId
            JOIN InvoiceLine il ON i.InvoiceId = il.InvoiceId
            JOIN Track t ON il.TrackId = t.TrackId
            JOIN Album al ON t.AlbumId = al.AlbumId
            JOIN Artist ar ON al.ArtistId = ar.ArtistId
            WHERE ar.Name != 'Various Artists'
            GROUP BY c.CustomerId, c.FirstName, c.LastName, ar.ArtistId, ar.Name
            HAVING COUNT(DISTINCT t.AlbumId) >= 3
            ORDER BY AlbumCount DESC, CustomerName ASC
        """
        
        cursor.execute(gt_sql)
        gt_rows = cursor.fetchall()
        result["ground_truth_row_count"] = len(gt_rows)
        
        # 4. Attempt to execute Agent's SQL against SQLite
        # Note: HSQLDB syntax in ODB might need slight adjustment for SQLite
        # e.g. "Table"."Column" quotes are fine in SQLite
        # e.g. CONCAT(a, b) -> a || b. 
        if result["extracted_sql"]:
            agent_sql = result["extracted_sql"]
            
            # Simple transpilation for common HSQLDB vs SQLite diffs
            # Replace CONCAT(a, ' ', b) with a || ' ' || b is hard with regex, 
            # but usually agents use || in Base or the GUI generates it.
            # If the agent uses HSQLDB specific functions, this might fail, 
            # so we treat execution failure as partial penalty, not total fail.
            
            try:
                cursor.execute(agent_sql)
                agent_rows = cursor.fetchall()
                result["row_count"] = len(agent_rows)
                result["execution_success"] = True
                
                # Compare results (set based comparison to be safe)
                # We normalize rows to string to avoid tuple vs list issues
                gt_set = set(str(r) for r in gt_rows)
                agent_set = set(str(r) for r in agent_rows)
                
                # Check overlap
                if gt_set == agent_set:
                    result["results_match"] = True
                elif len(agent_set.intersection(gt_set)) / len(gt_set) > 0.8:
                    # Allow minor formatting diffs if 80% matches
                    result["results_match"] = "partial"
                    
            except Exception as e:
                result["error"] = f"SQL Execution Error: {str(e)}"
        
        conn.close()

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Execute the inspection script
python3 /tmp/inspect_odb.py > /tmp/odb_analysis.json 2>/dev/null || echo '{"error": "Analysis script failed"}' > /tmp/odb_analysis.json

# 5. Create Final JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end": $(date +%s),
    "app_running": $APP_RUNNING,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size": $ODB_SIZE,
    "analysis": $(cat /tmp/odb_analysis.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="