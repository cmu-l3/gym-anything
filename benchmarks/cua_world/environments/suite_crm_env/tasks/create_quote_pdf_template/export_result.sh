#!/bin/bash
echo "=== Exporting create_quote_pdf_template results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read initial count to check for creation
INITIAL_COUNT=$(cat /tmp/initial_template_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aos_pdf_templates WHERE deleted=0" | tr -d '[:space:]')

# Verify if the target template was created
T_ID=$(suitecrm_db_query "SELECT id FROM aos_pdf_templates WHERE name='Federal Government Quote Template' AND deleted=0 LIMIT 1")

TEMPLATE_FOUND="false"
T_TYPE=""
T_ACTIVE=""
T_DESC=""

if [ -n "$T_ID" ]; then
    TEMPLATE_FOUND="true"
    # Query properties explicitly to avoid parsing multiline TSV issues
    T_TYPE=$(suitecrm_db_query "SELECT type FROM aos_pdf_templates WHERE id='$T_ID'")
    T_ACTIVE=$(suitecrm_db_query "SELECT active FROM aos_pdf_templates WHERE id='$T_ID'")
    T_DESC=$(suitecrm_db_query "SELECT description FROM aos_pdf_templates WHERE id='$T_ID'")
fi

# Use jq to safely escape all strings (especially the HTML description)
jq -n \
  --arg found "$TEMPLATE_FOUND" \
  --arg id "$T_ID" \
  --arg type "$T_TYPE" \
  --arg active "$T_ACTIVE" \
  --arg desc "$T_DESC" \
  --arg init_count "$INITIAL_COUNT" \
  --arg cur_count "$CURRENT_COUNT" \
  '{
    template_found: ($found == "true"),
    template_id: $id,
    type: $type,
    active: $active,
    description: $desc,
    initial_count: ($init_count | tonumber),
    current_count: ($cur_count | tonumber),
    created_during_task: (($cur_count | tonumber) > ($init_count | tonumber))
  }' > /tmp/create_quote_pdf_template_result.json

chmod 666 /tmp/create_quote_pdf_template_result.json 2>/dev/null || sudo chmod 666 /tmp/create_quote_pdf_template_result.json 2>/dev/null || true

echo "Result saved to /tmp/create_quote_pdf_template_result.json"
cat /tmp/create_quote_pdf_template_result.json
echo "=== Export complete ==="