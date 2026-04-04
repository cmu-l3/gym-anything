#!/bin/bash
# Setup for "service_catalog_department_setup" task
# ITSM Administrator: configure department, categories, subcategories, group, template

echo "=== Setting up Service Catalog Department Setup task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure export script is executable (Lesson 120)
chmod +x /workspace/tasks/service_catalog_department_setup/export_result.sh 2>/dev/null || true

ensure_sdp_running

# --- Record task start timestamp ---
date +%s > /tmp/task_start_timestamp

# --- Record baseline state ---
BASELINE_FILE="/tmp/service_catalog_department_setup_initial.json"

# Count existing departments (try multiple table names)
DEPT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM department;" 2>/dev/null | tr -d '[:space:]')
DEPT_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM sdorg;" 2>/dev/null | tr -d '[:space:]')

# Count existing categories
CAT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM category;" 2>/dev/null | tr -d '[:space:]')
CAT_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM categorydefn;" 2>/dev/null | tr -d '[:space:]')

# Count existing subcategories
SUBCAT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM subcategory;" 2>/dev/null | tr -d '[:space:]')

# Count existing groups
GROUP_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM supportgroup;" 2>/dev/null | tr -d '[:space:]')

# Count existing templates
TMPL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM workordertemplate;" 2>/dev/null | tr -d '[:space:]')
TMPL_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM requesttemplate;" 2>/dev/null | tr -d '[:space:]')

cat > "$BASELINE_FILE" << EOF
{
  "initial_dept_count": ${DEPT_COUNT:-0},
  "initial_dept_count_alt": ${DEPT_COUNT_ALT:-0},
  "initial_cat_count": ${CAT_COUNT:-0},
  "initial_cat_count_alt": ${CAT_COUNT_ALT:-0},
  "initial_subcat_count": ${SUBCAT_COUNT:-0},
  "initial_group_count": ${GROUP_COUNT:-0},
  "initial_template_count": ${TMPL_COUNT:-0},
  "initial_template_count_alt": ${TMPL_COUNT_ALT:-0},
  "task_start_time": $(date +%s%3N)
}
EOF

log "Baseline: depts=$DEPT_COUNT cats=$CAT_COUNT subcats=$SUBCAT_COUNT groups=$GROUP_COUNT templates=$TMPL_COUNT"

# Open Firefox on SDP main page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
sleep 5

take_screenshot /tmp/service_catalog_department_setup_start.png

echo "=== Service Catalog Department Setup task ready ==="
echo "Configure the service catalog for the Research Computing Services department."
echo "Log in with administrator / administrator"
