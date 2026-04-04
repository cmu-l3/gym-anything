#!/bin/bash
echo "=== Setting up rnaseq_qc_documentation task ==="

rm -f /tmp/rnaseq_qc_documentation_result.json 2>/dev/null || true
rm -f /tmp/rnaseq_initial_counts.json 2>/dev/null || true

source /workspace/scripts/task_utils.sh

# Record baseline counts — agent starts from blank state
INITIAL_PROJECT_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM projects;" | tr -d '[:space:]')
INITIAL_EXP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM experiments;" | tr -d '[:space:]')
INITIAL_TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules;" | tr -d '[:space:]')
INITIAL_REPO_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repositories;" | tr -d '[:space:]')

safe_write_json "/tmp/rnaseq_initial_counts.json" "{\"projects\": ${INITIAL_PROJECT_COUNT:-0}, \"experiments\": ${INITIAL_EXP_COUNT:-0}, \"tasks\": ${INITIAL_TASK_COUNT:-0}, \"repositories\": ${INITIAL_REPO_COUNT:-0}}"
echo "Baseline: projects=${INITIAL_PROJECT_COUNT}, experiments=${INITIAL_EXP_COUNT}, tasks=${INITIAL_TASK_COUNT}, repos=${INITIAL_REPO_COUNT}"

ensure_firefox_running "${SCINOTE_URL}/users/sign_in"
sleep 3
take_screenshot /tmp/rnaseq_qc_documentation_start_screenshot.png

echo "=== Setup complete. Agent must build full RNA-seq QC documentation from scratch. ==="
