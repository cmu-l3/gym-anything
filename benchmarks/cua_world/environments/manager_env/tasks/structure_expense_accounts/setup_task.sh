#!/bin/bash
echo "=== Setting up structure_expense_accounts task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial state of Chart of Accounts (simple count check)
# We can't easily query internal state without complex scraping, so we'll trust the post-check timestamp
echo "Recording initial state..."
touch /tmp/initial_state_recorded

# Open Manager.io at the Settings page to save one click, 
# but User still needs to find Chart of Accounts
echo "Opening Manager.io at Settings..."
open_manager_at "settings"

echo "=== Task setup complete ==="