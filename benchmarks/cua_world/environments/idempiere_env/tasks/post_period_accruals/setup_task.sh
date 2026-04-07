#!/bin/bash
# Setup script for post_period_accruals task
echo "=== Setting up post_period_accruals ==="

source /workspace/scripts/task_utils.sh

# Record existing GL journal IDs (baseline) for GardenWorld
idempiere_query "SELECT gl_journal_id FROM gl_journal WHERE ad_client_id=11 ORDER BY gl_journal_id" > /tmp/initial_journal_ids

INITIAL_JOURNAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM gl_journal WHERE ad_client_id=11")
echo "Initial GL journal count: ${INITIAL_JOURNAL_COUNT:-0}"
echo "${INITIAL_JOURNAL_COUNT:-0}" > /tmp/initial_journal_count

# Record GL batch count
INITIAL_BATCH_COUNT=$(idempiere_query "SELECT COUNT(*) FROM gl_journalbatch WHERE ad_client_id=11")
echo "Initial GL batch count: ${INITIAL_BATCH_COUNT:-0}"
echo "${INITIAL_BATCH_COUNT:-0}" > /tmp/initial_batch_count
idempiere_query "SELECT gl_journalbatch_id FROM gl_journalbatch WHERE ad_client_id=11 ORDER BY gl_journalbatch_id" > /tmp/initial_batch_ids

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate to dashboard
navigate_to_dashboard

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
