#!/bin/bash
# Setup script for journal_period_close task in Manager.io
# Records baseline journal entry count for anti-gaming.
# Opens Firefox at the Journal Entries module.

echo "=== Setting up journal_period_close task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

echo "$(date +%s)" > /tmp/manager_task_start_time

# ---------------------------------------------------------------------------
# Python: record baseline journal entry count
# ---------------------------------------------------------------------------
python3 - << 'PYEOF'
import requests
import re
import sys

MANAGER_URL = "http://localhost:8080"

s = requests.Session()
s.post(f"{MANAGER_URL}/login",
       data={"Username": "administrator"},
       allow_redirects=True)
biz_page = s.get(f"{MANAGER_URL}/businesses").text
m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
if not m:
    m = re.search(r'start\?([^"&\s]+)', biz_page)
if not m:
    print("ERROR: Could not get business key", file=sys.stderr)
    sys.exit(1)
biz_key = m.group(1)
s.get(f"{MANAGER_URL}/start?{biz_key}", allow_redirects=True)
print(f"Business key: {biz_key}")

je_page = s.get(f"{MANAGER_URL}/journal-entries?{biz_key}").text.replace('&amp;', '&')
je_count = len(set(re.findall(
    r'/journal-entry-form\?[^&"\']+&([a-f0-9-]{36})',
    je_page
)))
with open("/tmp/manager_task_je_count", "w") as f:
    f.write(str(je_count))
print(f"Baseline journal entry count: {je_count}")

print("Baseline recorded.")
PYEOF

take_screenshot /tmp/journal_period_close_start.png

echo "Opening Manager.io Journal Entries module..."
open_manager_at "journal_entries"

echo ""
echo "=== journal_period_close task setup complete ==="
echo ""
echo "TASK: Record three period-end adjusting journal entries"
echo ""
echo "JE-1 Depreciation (date: last day of current month):"
echo "  Dr Depreciation Expense     \$450.00"
echo "  Cr Accumulated Depreciation \$450.00"
echo "  Narration: Monthly depreciation — office equipment"
echo ""
echo "JE-2 Insurance (date: last day of current month):"
echo "  Dr Insurance Expense  \$300.00"
echo "  Cr Prepaid Insurance  \$300.00"
echo "  Narration: Monthly insurance expense recognition"
echo ""
echo "JE-3 Wages (date: last day of current month):"
echo "  Dr Wages Expense  \$2,400.00"
echo "  Cr Wages Payable  \$2,400.00"
echo "  Narration: Accrued wages for period end"
echo ""
echo "After creating entries, open the Balance Sheet report."
echo "Login: administrator / (empty password)"
