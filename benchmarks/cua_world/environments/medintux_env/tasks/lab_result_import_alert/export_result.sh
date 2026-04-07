#!/bin/bash
set -e
echo "=== Exporting Lab Result Task Data ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Database query to get notes created TODAY
# We join Rubriques with IndexNomPrenom to get patient names
# We select relevant fields: Name, FirstName, Note Title (Libelle), Content (Blob), Date, Time
echo "Querying database for new notes..."

SQL_QUERY="
SELECT 
    i.FchGnrl_NomDos,
    i.FchGnrl_Prenom,
    r.Rub_Libelle,
    CAST(r.Rub_Blob AS CHAR(10000) CHARACTER SET utf8),
    r.Rub_Date
FROM Rubriques r
JOIN IndexNomPrenom i ON r.Rub_IDDos = i.FchGnrl_IDDos
WHERE r.Rub_Date >= CURDATE()
  AND i.FchGnrl_NomDos IN ('DUBOIS', 'LEROY', 'MOREAU', 'PETIT');
"

# Create a temporary python script to export this to JSON securely
# doing it via python avoids complex bash string escaping issues with JSON
cat > /tmp/export_db_json.py << 'PYEOF'
import pymysql
import json
import datetime

conn = pymysql.connect(
    host='localhost',
    user='root',
    password='',
    db='DrTuxTest',
    charset='utf8mb4',
    cursorclass=pymysql.cursors.DictCursor
)

target_names = ['DUBOIS', 'LEROY', 'MOREAU', 'PETIT']

try:
    with conn.cursor() as cursor:
        # Get today's date in YYYY-MM-DD format
        today = datetime.date.today().strftime('%Y-%m-%d')
        
        # Query
        sql = """
        SELECT 
            i.FchGnrl_NomDos as last_name,
            i.FchGnrl_Prenom as first_name,
            r.Rub_Libelle as title,
            r.Rub_Blob as content,
            r.Rub_Date as date
        FROM Rubriques r
        JOIN IndexNomPrenom i ON r.Rub_IDDos = i.FchGnrl_IDDos
        WHERE r.Rub_Date >= %s
        AND i.FchGnrl_NomDos IN %s
        """
        cursor.execute(sql, (today, target_names))
        results = cursor.fetchall()
        
        # Convert bytes/dates to strings
        processed_results = []
        for row in results:
            if isinstance(row['content'], bytes):
                try:
                    row['content'] = row['content'].decode('utf-8', errors='ignore')
                except:
                    row['content'] = str(row['content'])
            if isinstance(row['date'], (datetime.date, datetime.datetime)):
                row['date'] = row['date'].strftime('%Y-%m-%d')
            processed_results.append(row)

        print(json.dumps({"notes": processed_results}, indent=2))
finally:
    conn.close()
PYEOF

# Run export
python3 /tmp/export_db_json.py > /tmp/db_results.json 2>/dev/null || echo '{"notes": []}' > /tmp/db_results.json

# Check if application is running
APP_RUNNING="false"
if pgrep -f "Manager.exe" > /dev/null; then
    APP_RUNNING="true"
fi

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)",
    "db_data": $(cat /tmp/db_results.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result preview:"
head -n 20 /tmp/task_result.json