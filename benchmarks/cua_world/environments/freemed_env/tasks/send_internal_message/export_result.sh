#!/bin/bash
echo "=== Exporting send_internal_message task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run dynamic Python script to search the FreeMED database for the message
echo "Running dynamic database search..."

cat > /tmp/search_db.py << 'EOF'
import mysql.connector
import json
import datetime

def serialize_datetime(obj):
    if isinstance(obj, datetime.datetime) or isinstance(obj, datetime.date): 
        return obj.isoformat()
    return str(obj)

result = {
    "found_anywhere": False,
    "found_in_messages": False,
    "found_in_pnotes": False,
    "recipient_id": None,
    "message_rows": []
}

try:
    conn = mysql.connector.connect(host="localhost", user="freemed", password="freemed", database="freemed")
    cursor = conn.cursor(dictionary=True)

    # 1. Get user ID for smitchell
    cursor.execute("SELECT id FROM user WHERE username='smitchell'")
    user_row = cursor.fetchone()
    if user_row:
        result["recipient_id"] = user_row["id"]

    target = "%lipid panel is back%"

    # 2. Check message tables
    cursor.execute("SHOW TABLES LIKE '%message%'")
    msg_tables = [list(r.values())[0] for r in cursor.fetchall()]

    for t in msg_tables:
        cursor.execute(f"SHOW COLUMNS FROM {t}")
        cols = [r['Field'] for r in cursor.fetchall() if 'text' in r['Type'].lower() or 'char' in r['Type'].lower()]
        for c in cols:
            try:
                cursor.execute(f"SELECT * FROM {t} WHERE {c} LIKE %s", (target,))
                rows = cursor.fetchall()
                if rows:
                    result["found_anywhere"] = True
                    result["found_in_messages"] = True
                    for row in rows:
                        row['_table'] = t
                        result["message_rows"].append(row)
            except Exception:
                pass

    # 3. Check pnotes (to catch gaming/incorrect workflow)
    cursor.execute("SHOW TABLES LIKE 'pnotes'")
    if cursor.fetchall():
        cursor.execute("SHOW COLUMNS FROM pnotes")
        cols = [r['Field'] for r in cursor.fetchall() if 'text' in r['Type'].lower() or 'char' in r['Type'].lower()]
        for c in cols:
            try:
                cursor.execute(f"SELECT * FROM pnotes WHERE {c} LIKE %s", (target,))
                rows = cursor.fetchall()
                if rows:
                    result["found_anywhere"] = True
                    result["found_in_pnotes"] = True
                    for row in rows:
                        row['_table'] = 'pnotes'
                        result["message_rows"].append(row)
            except Exception:
                pass

    # 4. Fallback search all tables
    if not result["found_anywhere"]:
        cursor.execute("SHOW TABLES")
        all_tables = [list(r.values())[0] for r in cursor.fetchall()]
        for t in all_tables:
            if t in msg_tables or t == 'pnotes': continue
            cursor.execute(f"SHOW COLUMNS FROM {t}")
            cols = [r['Field'] for r in cursor.fetchall() if 'text' in r['Type'].lower() or 'char' in r['Type'].lower()]
            for c in cols:
                try:
                    cursor.execute(f"SELECT * FROM {t} WHERE {c} LIKE %s", (target,))
                    rows = cursor.fetchall()
                    if rows:
                        result["found_anywhere"] = True
                        for row in rows:
                            row['_table'] = t
                            result["message_rows"].append(row)
                except Exception:
                    pass

except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, default=serialize_datetime)
EOF

python3 /tmp/search_db.py

echo "Search results:"
cat /tmp/task_result.json

echo ""
echo "=== Export Complete ==="