#!/bin/bash
echo "=== Exporting Void Settled Transaction Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_ticket_id.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# 1. Query Database for Result
# ==============================================================================

# We must kill the app to query the embedded Derby DB
kill_floreant

DERBY_LIB_DIR="/opt/floreantpos/lib"
CLASSPATH="$DERBY_LIB_DIR/derby.jar:$DERBY_LIB_DIR/derbytools.jar:$DERBY_LIB_DIR/derbyclient.jar"
DB_URL="jdbc:derby:/opt/floreantpos/database/derby-server/posdb"

# Create a SQL script to fetch details of tickets created AFTER initial_max_id
# We check TICKET table for VOIDED status and TRANSACTIONS table for payment proof.
cat > /tmp/export_data.sql << SQL_EOF
CONNECT '$DB_URL';

-- Output formatting to make parsing easier
app properties put 'ij.protocol' 'false';
app properties put 'ij.showNoConnectionsAtStart' 'false';
app properties put 'ij.showNoCountForSelect' 'true';

-- Select relevant columns for tickets created during task
SELECT 
    t.ID AS TICKET_ID, 
    t.VOIDED, 
    t.TOTAL_AMOUNT,
    (SELECT COUNT(*) FROM TRANSACTIONS tr WHERE tr.TICKET_ID = t.ID) AS TRANS_COUNT,
    (SELECT COUNT(*) FROM TICKET_ITEM ti WHERE ti.TICKET_ID = t.ID) AS ITEM_COUNT
FROM TICKET t 
WHERE t.ID > $INITIAL_MAX_ID;

EXIT;
SQL_EOF

echo "Running DB export query..."
# Run query and capture output
RAW_OUTPUT_FILE="/tmp/db_raw_output.txt"
java -cp "$CLASSPATH" org.apache.derby.tools.ij /tmp/export_data.sql > "$RAW_OUTPUT_FILE" 2>&1

echo "--- Raw DB Output ---"
cat "$RAW_OUTPUT_FILE"
echo "---------------------"

# ==============================================================================
# 2. Parse Output to JSON
# ==============================================================================
# ij output is tabular text. We need to parse it.
# Example output:
# TICKET_ID  |VOIDED|TOTAL_AMOUNT        |TRANS_COUNT|ITEM_COUNT 
# ---------------------------------------------------------------
# 152        |true  |15.50               |1          |2          

# We will use python to parse this text file cleanly
cat > /tmp/parse_results.py << 'PYEOF'
import sys
import json
import re

def parse_db_output(filename):
    tickets = []
    
    try:
        with open(filename, 'r') as f:
            lines = f.readlines()
            
        # Skip headers until we see the separator line (usually dashes)
        data_started = False
        for line in lines:
            if '-----' in line:
                data_started = True
                continue
            
            if not data_started:
                continue
                
            if not line.strip():
                continue
                
            # Parse row
            # Split by |
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 5:
                try:
                    ticket = {
                        "id": int(parts[0]),
                        "voided": parts[1].lower() == 'true',
                        "amount": float(parts[2]),
                        "transaction_count": int(parts[3]),
                        "item_count": int(parts[4])
                    }
                    tickets.append(ticket)
                except ValueError:
                    continue # Skip malformed lines
                    
    except Exception as e:
        sys.stderr.write(f"Error parsing DB output: {e}\n")
        
    return tickets

tickets = parse_db_output("/tmp/db_raw_output.txt")
result = {
    "tickets": tickets,
    "ticket_count": len(tickets),
    "task_start": int(sys.argv[1]),
    "task_end": int(sys.argv[2])
}

print(json.dumps(result, indent=2))
PYEOF

# Run parser
python3 /tmp/parse_results.py "$TASK_START" "$TASK_END" > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json

echo "=== Export Complete ==="