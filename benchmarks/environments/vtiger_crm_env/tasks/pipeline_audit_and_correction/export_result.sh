#!/bin/bash
# Export script for pipeline_audit_and_correction task

echo "=== Exporting pipeline_audit_and_correction results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/pipeline_audit_final.png

TASK_START=$(cat /tmp/pipeline_audit_start_ts 2>/dev/null || echo "0")

# --- Query all relevant deals ---

# Error 1: Nexus SCADA - Closed Won must have probability=100
NEXUS_DATA=$(vtiger_db_query "SELECT sales_stage, probability FROM vtiger_potential WHERE potentialname='Nexus SCADA Security Assessment' LIMIT 1")
NEXUS_STAGE=$(echo "$NEXUS_DATA" | awk -F'\t' '{print $1}')
NEXUS_PROB=$(echo "$NEXUS_DATA" | awk -F'\t' '{print $2}')

# Error 2: GreenLeaf - Needs Analysis must have probability 20-50
GREENLEAF_DATA=$(vtiger_db_query "SELECT sales_stage, probability FROM vtiger_potential WHERE potentialname='GreenLeaf IoT Factory Monitoring' LIMIT 1")
GREENLEAF_STAGE=$(echo "$GREENLEAF_DATA" | awk -F'\t' '{print $1}')
GREENLEAF_PROB=$(echo "$GREENLEAF_DATA" | awk -F'\t' '{print $2}')

# Error 3: Atlas - stale deal should be Closed Lost, probability 0
ATLAS_DATA=$(vtiger_db_query "SELECT sales_stage, probability, closingdate FROM vtiger_potential WHERE potentialname='Atlas Supply Chain Analytics' LIMIT 1")
ATLAS_STAGE=$(echo "$ATLAS_DATA" | awk -F'\t' '{print $1}')
ATLAS_PROB=$(echo "$ATLAS_DATA" | awk -F'\t' '{print $2}')
ATLAS_DATE=$(echo "$ATLAS_DATA" | awk -F'\t' '{print $3}')

# Error 4: Catalyst - stale deal should be Closed Lost, probability 0
CATALYST_DATA=$(vtiger_db_query "SELECT sales_stage, probability, closingdate FROM vtiger_potential WHERE potentialname='Catalyst LIMS Implementation' LIMIT 1")
CATALYST_STAGE=$(echo "$CATALYST_DATA" | awk -F'\t' '{print $1}')
CATALYST_PROB=$(echo "$CATALYST_DATA" | awk -F'\t' '{print $2}')
CATALYST_DATE=$(echo "$CATALYST_DATA" | awk -F'\t' '{print $3}')

# Explicit update: Horizon 5G amount
HORIZON_DATA=$(vtiger_db_query "SELECT amount FROM vtiger_potential WHERE potentialname='Horizon 5G Network Planning' LIMIT 1")
HORIZON_AMOUNT=$(echo "$HORIZON_DATA" | tr -d '[:space:]')

# Write result JSON using Python to avoid bash JSON escaping issues
python3 << PYEOF
import json

result = {
    "nexus_stage": """${NEXUS_STAGE:-}""",
    "nexus_probability": """${NEXUS_PROB:-}""",
    "greenleaf_stage": """${GREENLEAF_STAGE:-}""",
    "greenleaf_probability": """${GREENLEAF_PROB:-}""",
    "atlas_stage": """${ATLAS_STAGE:-}""",
    "atlas_probability": """${ATLAS_PROB:-}""",
    "atlas_closingdate": """${ATLAS_DATE:-}""",
    "catalyst_stage": """${CATALYST_STAGE:-}""",
    "catalyst_probability": """${CATALYST_PROB:-}""",
    "catalyst_closingdate": """${CATALYST_DATE:-}""",
    "horizon_amount": """${HORIZON_AMOUNT:-}""",
    "task_start": ${TASK_START}
}

with open('/tmp/pipeline_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
