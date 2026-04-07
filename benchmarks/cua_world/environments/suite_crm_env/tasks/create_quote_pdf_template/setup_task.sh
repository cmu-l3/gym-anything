#!/bin/bash
echo "=== Setting up create_quote_pdf_template task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial template count
INITIAL_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aos_pdf_templates WHERE deleted=0" | tr -d '[:space:]')
echo "Initial template count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/initial_template_count.txt
chmod 666 /tmp/initial_template_count.txt 2>/dev/null || true

# Verify the target template does not already exist
EXISTING_ID=$(suitecrm_db_query "SELECT id FROM aos_pdf_templates WHERE name='Federal Government Quote Template' AND deleted=0 LIMIT 1")
if [ -n "$EXISTING_ID" ]; then
    echo "WARNING: Target template already exists, soft deleting for a clean state."
    soft_delete_record "aos_pdf_templates" "name='Federal Government Quote Template'"
fi

# Ensure logged in and navigate to the PDF Templates list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=AOS_PDF_Templates&action=index"
sleep 3

# Take initial screenshot showing the start state
take_screenshot /tmp/task_initial.png

echo "=== create_quote_pdf_template task setup complete ==="