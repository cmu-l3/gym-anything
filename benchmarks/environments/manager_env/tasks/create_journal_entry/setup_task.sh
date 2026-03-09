#!/bin/bash
# Setup script for create_journal_entry task in Manager.io

echo "=== Setting up create_journal_entry task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

echo "Opening Manager.io Journal Entries module (New Journal Entry form)..."
open_manager_at "journal_entries" "new"

echo ""
echo "=== create_journal_entry task setup complete ==="
echo ""
echo "TASK: Create a manual journal entry in Manager.io (Northwind Traders)"
echo ""
echo "Journal entry details:"
echo "  Date:       Today"
echo "  Narration:  Prepaid office rent Q1"
echo "  Line 1:     Account: Accounting fees (or any expense account), Debit: 3000.00"
echo "  Line 2:     Account: Retained earnings (equity account),        Credit: 3000.00"
echo "  (Debits must equal Credits)"
echo ""
echo "Login: administrator / (empty password)"
