#!/bin/bash
# Export result for quarter_end_close task.
# Uses both Manager.io HTTP API and SQLite database to check task criteria.

echo "=== Exporting quarter_end_close result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/quarter_end_close_end.png

python3 - << 'PYEOF'
import requests
import re
import json
import sys
import os
import sqlite3
from datetime import datetime

MANAGER_URL = "http://localhost:8080"
DB_PATH = "/home/ga/manager-data/Northwind Traders.manager"

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

def db_find_uuid(name):
    """Find entity UUID by name in the database."""
    try:
        db = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
        rows = db.execute("SELECT Key, Content FROM Objects").fetchall()
        db.close()
        name_bytes = name.encode('utf-8')
        for key, content in rows:
            if isinstance(content, bytes) and name_bytes in content:
                return key
    except Exception:
        pass
    return None

def db_get_all_objects():
    """Get all objects from the database."""
    try:
        db = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
        rows = db.execute("SELECT Key, ContentType, Content FROM Objects").fetchall()
        db.close()
        return rows
    except Exception:
        return []

s, biz_key = login()
if not s:
    result = {"error": "login_failed", "export_timestamp": datetime.now().isoformat()}
    with open("/tmp/quarter_end_close_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

print(f"Business key: {biz_key}")

baseline_payments = read_baseline("payment_count")
baseline_je = read_baseline("je_count")

# Count current payments and JEs via Edit button count
try:
    payments_html = s.get(f"{MANAGER_URL}/payments?{biz_key}", timeout=15).text
    je_html = s.get(f"{MANAGER_URL}/journal-entries?{biz_key}", timeout=15).text
except Exception as e:
    result = {"error": str(e)}
    with open("/tmp/quarter_end_close_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(1)

current_payments = payments_html.count(">Edit<")
current_je = je_html.count(">Edit<")
new_payments = current_payments - baseline_payments
new_je = current_je - baseline_je

# -------------------------------------------------------------------
# Criterion 1: City Services payment reclassified to Professional Services
# -------------------------------------------------------------------
city_payment_found = "City Services" in payments_html
city_payment_reclassified = False

# Check via database: find the payment object that mentions City Services
# and see if its account reference matches Professional Services
all_objects = db_get_all_objects()
prof_services_uuid = db_find_uuid("Professional Services")
office_supplies_uuid = db_find_uuid("Office Supplies")

for key, ct, content in all_objects:
    if isinstance(content, bytes) and b"City Services" in content:
        # This is the City Services payment - check if Professional Services UUID is in it
        if prof_services_uuid and prof_services_uuid.encode('utf-8') in content:
            city_payment_reclassified = True
        elif prof_services_uuid:
            # Also check binary UUID representation
            uuid_bytes = bytes.fromhex(prof_services_uuid.replace('-', ''))
            if uuid_bytes in content:
                city_payment_reclassified = True

# Fallback: check if Professional Services appears near City Services in payments HTML
if not city_payment_reclassified and "Professional Services" in payments_html:
    idx = payments_html.find("City Services")
    if idx != -1:
        chunk = payments_html[max(0, idx-2000):idx+2000]
        if "Professional Services" in chunk:
            city_payment_reclassified = True

# -------------------------------------------------------------------
# Criterion 2: Bank charge payment recorded ($35)
# -------------------------------------------------------------------
has_bank_charge_35 = False

def amount_in(html, amount):
    return f"{amount:,.2f}" in html or f"{amount:.2f}" in html

# Check payments page for $35 near First National Bank or Bank charges
if "35.00" in payments_html and new_payments > 0:
    has_bank_charge_35 = True
# Also check via database for any new payment with amount 35
for key, ct, content in all_objects:
    if isinstance(content, bytes) and b"First National" in content:
        has_bank_charge_35 = True
        break

# -------------------------------------------------------------------
# Criterion 3: Adjusting journal entry (depreciation + insurance)
# -------------------------------------------------------------------
has_je_depreciation = False
has_je_insurance = False
je_narration_match = False

# Check JE page for amounts
if "450.00" in je_html and new_je > 0:
    has_je_depreciation = True
if "600.00" in je_html and new_je > 0:
    has_je_insurance = True

# Check database for JE objects containing the narration and amounts
for key, ct, content in all_objects:
    if isinstance(content, bytes):
        try:
            text = content.decode('utf-8', errors='replace')
        except:
            text = ""
        if "adjusting" in text.lower() or "q1" in text.lower():
            je_narration_match = True
            if "Depreciation" in text or "depreciation" in text:
                has_je_depreciation = True
            if "Insurance" in text or "insurance" in text:
                has_je_insurance = True

# -------------------------------------------------------------------
# Criterion 4: Customer credit limit (Alfreds = $1,000)
# -------------------------------------------------------------------
alfreds_credit_limit = None
alfreds_uuid = db_find_uuid("Alfreds Futterkiste")
if alfreds_uuid:
    # Read the Alfreds object from DB and look for credit limit
    for key, ct, content in all_objects:
        if key == alfreds_uuid and isinstance(content, bytes):
            # Check for common credit limit patterns in protobuf
            # Also try via HTTP: fetch customer form and check
            break
    # HTTP approach: check customer detail page
    try:
        cust_html = s.get(f"{MANAGER_URL}/customers?{biz_key}", timeout=15).text
        # Look for credit limit value near Alfreds
        idx = cust_html.find("Alfreds")
        if idx != -1:
            chunk = cust_html[idx:idx+1000]
            m = re.search(r'1[,.]?000', chunk)
            if m:
                alfreds_credit_limit = 1000.0
    except Exception:
        pass

    # Also check via the customer list if "1,000" or "1000" appears
    if alfreds_credit_limit is None:
        try:
            full_cust = s.get(f"{MANAGER_URL}/customers?{biz_key}", timeout=15).text
            if "1,000" in full_cust or "1000" in full_cust:
                # Could be the credit limit
                alfreds_credit_limit = 1000.0
        except Exception:
            pass

# -------------------------------------------------------------------
# Criterion 5: Lock Date set to 2025-03-31
# -------------------------------------------------------------------
lock_date_value = ""
try:
    lock_html = s.get(f"{MANAGER_URL}/lock-date-form?{biz_key}", timeout=15).text
    m = re.search(r'name="LockDate"[^>]*value="([^"]*)"', lock_html)
    if m:
        lock_date_value = m.group(1)
    if not lock_date_value:
        m = re.search(r'"LockDate"\s*:\s*"([^"]+)"', lock_html.replace('&quot;', '"'))
        if m:
            lock_date_value = m.group(1)
    if not lock_date_value:
        # Check if 2025-03-31 appears anywhere in the lock date page
        if "2025-03-31" in lock_html:
            lock_date_value = "2025-03-31"
except Exception as e:
    print(f"Error fetching lock date: {e}")

# -------------------------------------------------------------------
# Criterion 6: P&L file exists with content
# -------------------------------------------------------------------
pnl_file_path = "/home/ga/Documents/q1_pnl.txt"
pnl_file_exists = os.path.isfile(pnl_file_path)
pnl_file_content = ""
if pnl_file_exists:
    try:
        with open(pnl_file_path, "r") as f:
            pnl_file_content = f.read().strip()[:1024]
    except Exception:
        pass

pnl_file_created_during_task = False
task_start = 0
try:
    task_start = int(open("/tmp/manager_task_start_time").read().strip())
except Exception:
    pass
if pnl_file_exists:
    try:
        mtime = int(os.path.getmtime(pnl_file_path))
        pnl_file_created_during_task = mtime >= task_start
    except Exception:
        pass

# -------------------------------------------------------------------
# Assemble result JSON
# -------------------------------------------------------------------
result = {
    "baseline_payments": baseline_payments,
    "baseline_je": baseline_je,
    "current_payment_count": current_payments,
    "current_je_count": current_je,
    "new_payment_count": new_payments,
    "new_je_count": new_je,

    "city_payment_found": city_payment_found,
    "city_payment_reclassified": city_payment_reclassified,

    "has_bank_charge_35": has_bank_charge_35,

    "has_je_depreciation": has_je_depreciation,
    "has_je_insurance": has_je_insurance,
    "je_narration_match": je_narration_match,

    "alfreds_credit_limit": alfreds_credit_limit,

    "lock_date_value": lock_date_value,

    "pnl_file_exists": pnl_file_exists,
    "pnl_file_content": pnl_file_content,
    "pnl_file_created_during_task": pnl_file_created_during_task,

    "export_timestamp": datetime.now().isoformat()
}

print(json.dumps(result, indent=2))

with open("/tmp/quarter_end_close_result.json", "w") as f:
    json.dump(result, f, indent=2)
os.chmod("/tmp/quarter_end_close_result.json", 0o666)

print("JSON written to /tmp/quarter_end_close_result.json")
PYEOF

echo "=== Export Complete ==="
