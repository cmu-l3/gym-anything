#!/bin/bash
# Export results for "configure_sla" task
# Scrapes the database for the created SLA and its properties.

echo "=== Exporting Configure SLA Results ==="
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Extract SLA Data using Python
# This script connects to the DB, looks for the specific SLA, and tries to reconstruct the priority/time mappings.
cat > /tmp/extract_sla.py << 'PYEOF'
import psycopg2
import json
import sys
import time

DB_CONFIG = {"host": "localhost", "port": 65432, "user": "postgres", "database": "servicedesk"}
SLA_NAME = "Premium Support SLA"

result = {
    "sla_found": False,
    "sla_id": None,
    "created_time": 0,
    "priorities": {},
    "raw_dump": {},
    "error": None
}

try:
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    # 1. Find the SLA Definition
    # Schema varies, so we search dynamically
    sla_table = None
    sla_id_col = None
    
    # Try common table names for SLA definitions
    potential_sla_tables = ["sladefinition", "slaconfiguration", "servicelevelagreement"]
    
    for tbl in potential_sla_tables:
        try:
            cur.execute(f"SELECT * FROM {tbl} WHERE name = %s", (SLA_NAME,))
            row = cur.fetchone()
            if row:
                sla_table = tbl
                # Assume first column is ID usually
                col_names = [desc[0] for desc in cur.description]
                result["raw_dump"]["sla_record"] = dict(zip(col_names, row))
                
                # Try to identify ID column (usually ends in 'id' or is the first one)
                for col in col_names:
                    if 'id' in col.lower() and 'site' not in col.lower():
                        result["sla_id"] = row[col_names.index(col)]
                        sla_id_col = col
                        break
                if not result["sla_id"]: 
                     result["sla_id"] = row[0] # Fallback to first col
                
                result["sla_found"] = True
                break
        except Exception as e:
            conn.rollback()

    # 2. If SLA found, try to find Time Limits (Response/Resolution)
    # This is tricky without exact schema. We look for tables linking SLA_ID to Priority.
    # We will try to dump anything that looks like a mapping.
    
    if result["sla_found"] and result["sla_id"]:
        # Try to guess creation time if available
        # Sometimes stored in createdtime or similar
        for k, v in result["raw_dump"]["sla_record"].items():
            if 'time' in k.lower() and isinstance(v, int) and v > 1000000000:
                result["created_time"] = v
                break

        # Search for mapping tables. 
        # Strategy: Search tables that might contain the SLA ID value
        # This is a heuristic scan.
        
        # NOTE: In many SDP versions, `slaret` or `slalimit` holds the times.
        # `slaret` usually has: slaid, priorityid, response_time, resolution_time (in milliseconds or minutes)
        
        mapping_tables = ["slaret", "slalimit", "sla_priority_mapping", "slacriteria"]
        
        for mt in mapping_tables:
            try:
                # Naive query: select where any column equals the SLA ID
                # Getting column names first
                cur.execute(f"SELECT * FROM {mt} LIMIT 0")
                m_cols = [desc[0] for desc in cur.description]
                
                # Construct query
                # We are looking for rows where the SLA ID is present
                query_parts = [f"{c} = {result['sla_id']}" for c in m_cols if 'id' in c.lower()]
                if not query_parts: continue
                
                query = f"SELECT * FROM {mt} WHERE " + " OR ".join(query_parts)
                
                cur.execute(query)
                rows = cur.fetchall()
                
                if rows:
                    result["raw_dump"][mt] = []
                    for r in rows:
                        rec = dict(zip(m_cols, r))
                        result["raw_dump"][mt].append(rec)
                        
                        # Try to parse into our standardized "priorities" format
                        # Heuristic: Look for 'res' (resolution) and 'resp' (response) columns
                        # And 'prio' (priority) columns
                        prio_id = None
                        resp_time = 0
                        res_time = 0
                        
                        for k, v in rec.items():
                            k_lower = k.lower()
                            if 'priority' in k_lower: prio_id = v
                            if 'response' in k_lower and isinstance(v, int): resp_time = v
                            if 'resolution' in k_lower or 'resolve' in k_lower: 
                                if isinstance(v, int): res_time = v
                        
                        if prio_id is not None:
                            # Map priority ID to name if possible, or keep ID
                            # We'll fetch priority names next
                            result["priorities"][str(prio_id)] = {
                                "response_raw": resp_time,
                                "resolution_raw": res_time
                            }
            except Exception as e:
                conn.rollback()

    # 3. Get Priority Names mapping
    # Table usually `prioritydefinition` or `priority`
    priority_map = {}
    try:
        cur.execute("SELECT * FROM prioritydefinition")
        rows = cur.fetchall()
        cols = [desc[0] for desc in cur.description]
        for r in rows:
            rec = dict(zip(cols, r))
            # Find ID and Name
            pid = None
            pname = None
            for k,v in rec.items():
                if 'id' in k.lower(): pid = str(v)
                if 'name' in k.lower(): pname = v
            if pid and pname:
                priority_map[pid] = pname
    except:
        conn.rollback()

    # 4. Enrich priorities with names
    if priority_map and result["priorities"]:
        new_priorities = {}
        for pid, data in result["priorities"].items():
            pname = priority_map.get(pid, f"Unknown_{pid}")
            new_priorities[pname] = data
        result["priorities"] = new_priorities

except Exception as e:
    result["error"] = str(e)
finally:
    if conn: conn.close()

print(json.dumps(result, indent=2))
PYEOF

# 4. Run extraction and save to JSON
python3 /tmp/extract_sla.py > /tmp/sla_data.json

# 5. Get current SLA count for "Do Nothing" check
INITIAL_COUNT=$(cat /tmp/initial_sla_count.txt 2>/dev/null || echo "0")
# Re-run count script
python3 /tmp/count_slas.py > /tmp/final_sla_count.txt
FINAL_COUNT=$(cat /tmp/final_sla_count.txt 2>/dev/null || echo "0")

# 6. Assemble Final Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_sla_count": $INITIAL_COUNT,
    "final_sla_count": $FINAL_COUNT,
    "db_extraction": $(cat /tmp/sla_data.json),
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false")
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="