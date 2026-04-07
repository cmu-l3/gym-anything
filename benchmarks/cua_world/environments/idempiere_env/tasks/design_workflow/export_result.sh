#!/bin/bash
echo "=== Exporting design_workflow result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Client ID
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# 1. Query for the specific Workflow Header
echo "--- Querying Workflow Header ---"
# Get ID, Name, TableID, StartNodeID, IsActive, Created timestamp
WF_DATA=$(idempiere_query "SELECT AD_Workflow_ID, Name, AD_Table_ID, AD_WF_Node_ID, IsActive, Created FROM AD_Workflow WHERE Name='Project_Initiation_WF' AND AD_Client_ID=$CLIENT_ID AND IsActive='Y' ORDER BY Created DESC LIMIT 1" 2>/dev/null)

WF_ID=""
WF_NAME=""
WF_TABLE_ID=""
WF_START_NODE_ID=""
WF_IS_ACTIVE=""
WF_CREATED=""
TABLE_NAME=""

if [ -n "$WF_DATA" ]; then
    WF_ID=$(echo "$WF_DATA" | cut -d'|' -f1)
    WF_NAME=$(echo "$WF_DATA" | cut -d'|' -f2)
    WF_TABLE_ID=$(echo "$WF_DATA" | cut -d'|' -f3)
    WF_START_NODE_ID=$(echo "$WF_DATA" | cut -d'|' -f4)
    WF_IS_ACTIVE=$(echo "$WF_DATA" | cut -d'|' -f5)
    WF_CREATED=$(echo "$WF_DATA" | cut -d'|' -f6)

    # Get Table Name if ID exists
    if [ -n "$WF_TABLE_ID" ]; then
        TABLE_NAME=$(idempiere_query "SELECT TableName FROM AD_Table WHERE AD_Table_ID=$WF_TABLE_ID" 2>/dev/null)
    fi
fi

# 2. Query Nodes if Workflow exists
NODES_JSON="[]"
TRANSITIONS_JSON="[]"
START_NODE_NAME=""

if [ -n "$WF_ID" ]; then
    echo "--- Querying Nodes for Workflow ID $WF_ID ---"
    
    # Get all nodes: ID, Name
    # Using python to format as JSON to handle potential special chars safely
    NODES_RAW=$(idempiere_query "SELECT AD_WF_Node_ID, Name FROM AD_WF_Node WHERE AD_Workflow_ID=$WF_ID AND IsActive='Y'" 2>/dev/null)
    
    # Check which one is start node
    if [ -n "$WF_START_NODE_ID" ]; then
        START_NODE_NAME=$(idempiere_query "SELECT Name FROM AD_WF_Node WHERE AD_WF_Node_ID=$WF_START_NODE_ID" 2>/dev/null)
    fi

    # 3. Query Transitions (Node Next)
    # Join to get source node name and target node name
    # AD_WF_NodeNext links a Node (Parent) to a Next Node (AD_WF_Next_ID)
    echo "--- Querying Transitions ---"
    TRANSITIONS_RAW=$(idempiere_query "SELECT n.Name, next.Name FROM AD_WF_NodeNext nn JOIN AD_WF_Node n ON nn.AD_WF_Node_ID = n.AD_WF_Node_ID JOIN AD_WF_Node next ON nn.AD_WF_Next_ID = next.AD_WF_Node_ID WHERE n.AD_Workflow_ID=$WF_ID AND nn.IsActive='Y'" 2>/dev/null)
fi

# 4. Construct JSON Result
# We use a python script to generate valid JSON from the raw pipe-delimited DB output
python3 -c "
import json
import sys
import time
from datetime import datetime

def parse_db_output(raw_str):
    if not raw_str: return []
    lines = raw_str.strip().split('\n')
    return [line.split('|') for line in lines if line]

wf_found = '${WF_ID}' != ''
nodes = parse_db_output('''$NODES_RAW''')
transitions = parse_db_output('''$TRANSITIONS_RAW''')

node_list = [{'id': n[0], 'name': n[1]} for n in nodes] if nodes else []
trans_list = [{'source': t[0], 'target': t[1]} for t in transitions] if transitions else []

# Parse Created timestamp (approximate check)
created_ts = 0
try:
    # Postgres format often: 2024-10-25 14:30:00.123
    # We just grab the string for display, strict TS check done in python verifier if needed
    pass
except:
    pass

result = {
    'workflow_found': wf_found,
    'workflow_id': '${WF_ID}',
    'workflow_name': '${WF_NAME}',
    'table_name': '${TABLE_NAME}',
    'start_node_name': '${START_NODE_NAME}',
    'is_active': '${WF_IS_ACTIVE}',
    'nodes': node_list,
    'transitions': trans_list,
    'task_start': ${TASK_START},
    'task_end': ${TASK_END},
    'screenshot_path': '/tmp/task_final.png'
}

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Adjust permissions
chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="