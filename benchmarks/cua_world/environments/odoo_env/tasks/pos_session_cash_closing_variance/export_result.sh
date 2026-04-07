#!/bin/bash
# Export script for pos_session_cash_closing_variance

echo "=== Exporting POS Task Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Read Target Session ID
if [ ! -f /tmp/target_session_id.txt ]; then
    echo "ERROR: Session ID not found."
    echo '{"error": "setup_failed"}' > /tmp/task_result.json
    exit 0
fi
SESSION_ID=$(cat /tmp/target_session_id.txt)

# 3. Query Odoo for Session Status
python3 << PYEOF
import xmlrpc.client
import json
import sys

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

session_id = $SESSION_ID

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
    
    # Get Session Data
    # Fields to check:
    # state: should be 'closed'
    # cash_register_balance_end_real: Agent entered value (should be 445)
    # cash_register_balance_end: Theoretical value (should be 450)
    # cash_register_difference: (should be -5)
    
    session = models.execute_kw(DB, uid, PASSWORD, 'pos.session', 'read', 
        [[session_id]], 
        {'fields': [
            'name', 'state', 
            'cash_register_balance_start', 
            'cash_register_balance_end', 
            'cash_register_balance_end_real', 
            'cash_register_difference',
            'stop_at'
        ]})[0]
        
    # Check for Account Move (Journal Entry)
    # When a session is closed with variance, a move is posted.
    # We look for a move associated with this session.
    # In Odoo POS, the move is usually linked via 'move_id' in pos.session (if configured to post per session)
    # or we check the account.move.line for the P&L account.
    
    move_id = session.get('move_id') # This might be the main entry
    
    # Check if a loss was recorded.
    # Difference is -5.0. This implies a Credit to Cash (Asset down) and Debit to Loss (Expense up).
    # We just assume if state is closed and difference is recorded, Odoo did its job.
    
    result = {
        "session_id": session_id,
        "state": session.get('state'),
        "closing_cash_real": session.get('cash_register_balance_end_real'),
        "theoretical_cash": session.get('cash_register_balance_end'),
        "difference": session.get('cash_register_difference'),
        "stop_at": session.get('stop_at')
    }
    
    with open('/tmp/pos_result_data.json', 'w') as f:
        json.dump(result, f)
        
except Exception as e:
    print(f"Export failed: {e}")
    with open('/tmp/pos_result_data.json', 'w') as f:
        json.dump({"error": str(e)}, f)

PYEOF

# 4. Create Final JSON
# We combine the python output with shell metadata
if [ -f /tmp/pos_result_data.json ]; then
    cat /tmp/pos_result_data.json > /tmp/task_result.json
else
    echo '{"error": "export_script_failed"}' > /tmp/task_result.json
fi

# Adjust permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json