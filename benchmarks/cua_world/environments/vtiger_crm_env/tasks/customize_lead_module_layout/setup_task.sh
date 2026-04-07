#!/bin/bash
echo "=== Setting up customize_lead_module_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Reset any previous layout modifications for Leads module
echo "Resetting Leads layout to default state..."
TABID=$(vtiger_db_query "SELECT tabid FROM vtiger_tab WHERE name='Leads' LIMIT 1" | tr -d '[:space:]')

if [ -n "$TABID" ]; then
    # Get the default block ID (usually LBL_LEAD_INFORMATION)
    DEFAULT_BLOCK=$(vtiger_db_query "SELECT blockid FROM vtiger_blocks WHERE tabid=$TABID AND blocklabel='LBL_LEAD_INFORMATION' LIMIT 1" | tr -d '[:space:]')
    
    if [ -n "$DEFAULT_BLOCK" ]; then
        # Find any custom blocks named 'Qualification Metrics' and delete them
        CUSTOM_BLOCKS=$(vtiger_db_query "SELECT blockid FROM vtiger_blocks WHERE tabid=$TABID AND blocklabel='Qualification Metrics'")
        if [ -n "$CUSTOM_BLOCKS" ]; then
            for B_ID in $CUSTOM_BLOCKS; do
                # Move fields back to default block
                vtiger_db_query "UPDATE vtiger_field SET block=$DEFAULT_BLOCK WHERE block=$B_ID"
                # Delete custom block
                vtiger_db_query "DELETE FROM vtiger_blocks WHERE blockid=$B_ID"
            done
        fi
        
        # Ensure target fields are in the default block and visible (presence=2 means active/visible in Vtiger)
        vtiger_db_query "UPDATE vtiger_field SET presence=2, block=$DEFAULT_BLOCK WHERE tabid=$TABID AND fieldname IN ('industry', 'annualrevenue', 'noofemployees', 'fax')"
    fi
fi

# 2. Ensure logged in and navigate to Vtiger home (forces agent to find settings)
ensure_vtiger_logged_in "http://localhost:8000/"
sleep 3

# 3. Take initial screenshot
take_screenshot /tmp/layout_customization_initial.png

echo "=== customize_lead_module_layout task setup complete ==="
echo "Task: Customize Lead Module layout"
echo "Agent should navigate to Settings -> Module Layouts & Fields -> Leads"