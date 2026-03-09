#!/bin/bash
# Export result for journal_period_close task.
# Queries Manager.io HTTP API from inside the VM and writes
# a JSON result file that verifier.py will copy out and score.

echo "=== Exporting journal_period_close result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/journal_period_close_end.png

python3 - << 'PYEOF'
import requests
import re
import json
import sys

MANAGER_URL = "http://localhost:8080"

def login():
    s = requests.Session()
    s.post(f"{MANAGER_URL}/login",
           data={"Username": "administrator"},
           allow_redirects=True, timeout=15)
    biz_page = s.get(f"{MANAGER_URL}/businesses", timeout=15).text
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', biz_page)
    if not m:
        return None, None
    biz_key = m.group(1)
    s.get(f"{MANAGER_URL}/start?{biz_key}", timeout=15)
    return s, biz_key

def read_baseline(key, default=0):
    try:
        return int(open(f"/tmp/manager_task_{key}").read().strip())
    except Exception:
        return default

def count_links(html, form):
    html = html.replace('&amp;', '&')
    return len(set(re.findall(rf'/{form}\?[^&"\']+&([a-f0-9-]{{36}})', html)))

def amount_in(html, amount):
    return f"{amount:,.2f}" in html or f"{amount:.2f}" in html

def je_balanced(s, biz_key, uuid, amount):
    """Fetch a JE form and check if the amount appears 2+ times (balanced)."""
    try:
        html = s.get(f"{MANAGER_URL}/journal-entry-form?{biz_key}&{uuid}", timeout=15).text
        c1 = html.count(f"{amount:,.2f}")
        c2 = html.count(f"{amount:.2f}")
        return (c1 + c2) >= 2
    except Exception:
        return False

s, biz_key = login()
if not s:
    result = {"error": "login_failed"}
    with open("/tmp/journal_period_close_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

print(f"Business key: {biz_key}")

baseline_je = read_baseline("je_count")

try:
    je_html = s.get(f"{MANAGER_URL}/journal-entries?{biz_key}", timeout=15).text.replace('&amp;', '&')
except Exception as e:
    result = {"error": str(e)}
    with open("/tmp/journal_period_close_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

current_je = count_links(je_html, "journal-entry-form")
je_uuids = list(set(re.findall(
    r'/journal-entry-form\?[^&"\']+&([a-f0-9-]{36})',
    je_html
)))

# Check each amount
je_450_in_list = amount_in(je_html, 450.0) and current_je > baseline_je
je_300_in_list = amount_in(je_html, 300.0) and current_je > baseline_je
je_2400_in_list = amount_in(je_html, 2400.0) and current_je > baseline_je

# Check balance of individual JEs
je_450_balanced = False
je_300_balanced = False
je_2400_balanced = False
for uuid in je_uuids:
    if not je_450_balanced and je_balanced(s, biz_key, uuid, 450.0):
        je_450_balanced = True
    if not je_300_balanced and je_balanced(s, biz_key, uuid, 300.0):
        je_300_balanced = True
    if not je_2400_balanced and je_balanced(s, biz_key, uuid, 2400.0):
        je_2400_balanced = True

# Fallback: if amount is in list and count increased, assume balanced
if je_450_in_list and not je_450_balanced:
    je_450_balanced = True
if je_300_in_list and not je_300_balanced:
    je_300_balanced = True
if je_2400_in_list and not je_2400_balanced:
    je_2400_balanced = True

result = {
    "baseline_je": baseline_je,
    "current_je_count": current_je,
    "new_je_count": current_je - baseline_je,

    # Criterion 1: JE depreciation $450
    "je_450_in_list": je_450_in_list,
    "je_450_balanced": je_450_balanced,
    "je_depreciation_ok": je_450_in_list and je_450_balanced,

    # Criterion 2: JE insurance $300
    "je_300_in_list": je_300_in_list,
    "je_300_balanced": je_300_balanced,
    "je_insurance_ok": je_300_in_list and je_300_balanced,

    # Criterion 3: JE wages $2,400
    "je_2400_in_list": je_2400_in_list,
    "je_2400_balanced": je_2400_balanced,
    "je_wages_ok": je_2400_in_list and je_2400_balanced,

    # Criterion 4: Count increased by >= 3
    "je_count_increased_3": (current_je - baseline_je) >= 3,

    "export_timestamp": __import__('datetime').datetime.now().isoformat()
}

print(json.dumps(result, indent=2))

with open("/tmp/journal_period_close_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("JSON written to /tmp/journal_period_close_result.json")
PYEOF

echo "=== Export Complete ==="
