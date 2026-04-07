#!/bin/bash
echo "=== Exporting customize_contacts_travel_layout results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Read initial states
MAX_BLOCK_ID=$(cat /tmp/initial_max_block_id.txt 2>/dev/null || echo "0")
MAX_FIELD_ID=$(cat /tmp/initial_max_field_id.txt 2>/dev/null || echo "0")

# Write a robust PHP script to extract the exact schema state
cat > /tmp/export_schema.php << PHPEOF
<?php
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
\$conn = new mysqli('vtiger-db', 'vtiger', 'vtiger_pass', 'vtiger');
if (\$conn->connect_error) {
    die(json_encode(array('error' => 'DB Connection failed')));
}

\$res = array();
\$res['initial_max_block_id'] = $MAX_BLOCK_ID;
\$res['initial_max_field_id'] = $MAX_FIELD_ID;

// Get Contacts Tab ID
\$tab_q = \$conn->query("SELECT tabid FROM vtiger_tab WHERE name='Contacts'");
if (\$tab_q && \$tab_q->num_rows > 0) {
    \$tabid = \$tab_q->fetch_assoc()['tabid'];
} else {
    \$tabid = 4; // default for Contacts
}

// Find the block
\$block_q = \$conn->query("SELECT blockid, blocklabel FROM vtiger_blocks WHERE tabid=\$tabid AND blocklabel='Travel Preferences'");
if (\$block_q && \$block_q->num_rows > 0) {
    \$block = \$block_q->fetch_assoc();
    \$res['block'] = \$block;
    
    \$blockid = \$block['blockid'];
    \$res['fields'] = array();
    \$res['picklist_values'] = array();
    
    // Find fields in this block
    \$fields_q = \$conn->query("SELECT fieldid, fieldlabel, fieldname, uitype, block FROM vtiger_field WHERE tabid=\$tabid AND block=\$blockid");
    if (\$fields_q) {
        while(\$f = \$fields_q->fetch_assoc()) {
            \$res['fields'][] = \$f;
            
            // Extract picklist values if applicable
            if (in_array(\$f['uitype'], array(15, 16, 33))) {
                \$fname = \$f['fieldname'];
                \$vals_q = \$conn->query("SELECT \$fname as val FROM vtiger_\$fname ORDER BY sortorderid ASC");
                \$vals = array();
                if (\$vals_q) {
                    while(\$v = \$vals_q->fetch_assoc()) {
                        \$vals[] = \$v['val'];
                    }
                }
                \$res['picklist_values'][\$f['fieldlabel']] = \$vals;
            }
        }
    }
} else {
    \$res['block'] = null;
}

echo json_encode(\$res);
?>
PHPEOF

# Execute the PHP script inside the vtiger-app container to get the JSON result
docker cp /tmp/export_schema.php vtiger-app:/tmp/export_schema.php
docker exec vtiger-app php /tmp/export_schema.php > /tmp/schema_result_temp.json

# Read the JSON result and append standard task variables
SCHEMA_JSON=$(cat /tmp/schema_result_temp.json)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "schema_data": $SCHEMA_JSON,
    "timestamp": "$(date +%s)",
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Use safe write
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" /tmp/schema_result_temp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json | jq . || cat /tmp/task_result.json
echo "=== Export complete ==="