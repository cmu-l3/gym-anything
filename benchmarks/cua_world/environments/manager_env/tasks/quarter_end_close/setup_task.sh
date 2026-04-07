#!/bin/bash
# Setup script for quarter_end_close task.
# Seeds Northwind Traders with a full quarter of transaction data including
# deliberate errors for the agent to find and correct.
#
# NOTE: Uses the form API for entity creation and SQLite for UUID lookups.
# Manager.io v26 uses base64-encoded URL keys, so UUIDs are read from the
# .manager SQLite database files instead of HTML parsing.

echo "=== Setting up quarter_end_close task ==="

source /workspace/scripts/task_utils.sh

wait_for_manager 60

# Clean up any previous output BEFORE recording start time
rm -f /home/ga/Documents/q1_pnl.txt
mkdir -p /home/ga/Documents

echo "$(date +%s)" > /tmp/manager_task_start_time

# ---------------------------------------------------------------------------
# Python: seed all Q1 2025 data
# ---------------------------------------------------------------------------
python3 - << 'PYEOF'
import requests, re, json, sys, sqlite3, time, glob

MANAGER_URL = "http://localhost:8080"

def find_db_path():
    """Find the Northwind Traders .manager database file."""
    candidates = glob.glob("/home/ga/manager-data/*.manager")
    for c in candidates:
        if "Northwind Traders" in c:
            return c
    # Fallback: use the largest .manager file
    candidates.sort(key=lambda f: __import__('os').path.getsize(f), reverse=True)
    return candidates[0] if candidates else None

def login_and_get_bizkey():
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
        return None, None
    biz_key = m.group(1)
    s.get(f"{MANAGER_URL}/start?{biz_key}", allow_redirects=True)
    return s, biz_key

def get_form_field(s, form_url):
    form_page = s.get(form_url).text
    m = re.search(r'name="([a-f0-9-]{36})" value="\{\}"', form_page)
    return m.group(1) if m else None

def post_entity(s, form_url, data_dict):
    field_name = get_form_field(s, form_url)
    if not field_name:
        return None
    resp = s.post(form_url,
                  files={field_name: (None, json.dumps(data_dict))},
                  allow_redirects=True)
    return resp.status_code

def entity_exists_http(s, list_url, name):
    """Check if entity exists by searching the list page HTML."""
    page = s.get(list_url).text
    return name in page

def db_find_uuid(db_path, name):
    """Find entity UUID by name in the Manager.io SQLite database."""
    if not db_path:
        return None
    try:
        db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        rows = db.execute("SELECT Key, Content FROM Objects").fetchall()
        db.close()
        name_bytes = name.encode('utf-8')
        for key, content in rows:
            if isinstance(content, bytes) and name_bytes in content:
                return key
    except Exception as e:
        print(f"  DB error looking for '{name}': {e}")
    return None

# =========================================================================
# MAIN
# =========================================================================
s, biz_key = login_and_get_bizkey()
if not s:
    sys.exit(1)
print(f"Business key: {biz_key}")

DB_PATH = find_db_path()
print(f"Database path: {DB_PATH}")

# -------------------------------------------------------------------
# Phase 0: Enable required sidebar tabs
# The post_start cache may not have all modules enabled.
# -------------------------------------------------------------------
print("\n--- Phase 0: Enabling sidebar tabs ---")
tabs_enabled = False
for attempt in range(3):
    time.sleep(2)
    summary_html = s.get(f"{MANAGER_URL}/summary-view?{biz_key}").text
    m_tabs = re.search(r'tabs-form\?([^"]+)', summary_html)
    if not m_tabs:
        print(f"  Attempt {attempt+1}: Could not find tabs-form URL, retrying...")
        continue
    tabs_query = m_tabs.group(1)
    tabs_form_html = s.get(f"{MANAGER_URL}/tabs-form?{tabs_query}").text
    m_field = re.search(r'name="([a-f0-9-]{36})" value="\{\}"', tabs_form_html)
    if not m_field:
        print(f"  Attempt {attempt+1}: Could not find tabs form field, retrying...")
        continue
    tabs_field = m_field.group(1)
    tabs_data = {
        "BankAndCashAccounts": True,
        "Receipts": True,
        "Payments": True,
        "Customers": True,
        "SalesInvoices": True,
        "CreditNotes": True,
        "Suppliers": True,
        "PurchaseInvoices": True,
        "DebitNotes": True,
        "InventoryItems": True,
        "JournalEntries": True,
        "Reports": True,
    }
    resp = s.post(f"{MANAGER_URL}/tabs-form?{tabs_query}",
                  files={tabs_field: (None, json.dumps(tabs_data))},
                  allow_redirects=True)
    print(f"  Tabs POST: HTTP {resp.status_code}")
    # Verify
    verify_html = s.get(f"{MANAGER_URL}/summary-view?{biz_key}").text
    if "Payments" in verify_html and "Sales Invoices" in verify_html:
        tabs_enabled = True
        print("  Tabs verified: All required tabs visible")
        break
    else:
        print(f"  Attempt {attempt+1}: Tabs not visible after POST, retrying...")
if not tabs_enabled:
    print("  WARNING: Could not enable all tabs after 3 attempts")

# -------------------------------------------------------------------
# Phase 1: Create Chart of Accounts entries
# Manager.io v26 uses different form endpoints for Balance Sheet vs P&L accounts:
#   - balance-sheet-account-form      (for Asset, Liability, Equity accounts)
#   - profit-and-loss-statement-account-form  (for Revenue, Expense accounts)
# The correct form URL is extracted from the Chart of Accounts page links.
# -------------------------------------------------------------------
print("\n--- Phase 1: Creating accounts ---")
accounts_to_create = [
    ("Cost of Goods Sold", "pnl"),
    ("Office Supplies", "pnl"),
    ("Professional Services", "pnl"),
    ("Depreciation Expense", "pnl"),
    ("Insurance Expense", "pnl"),
    ("Accumulated Depreciation", "bs"),
    ("Prepaid Insurance", "bs"),
]

coa_url = f"{MANAGER_URL}/chart-of-accounts?{biz_key}"
coa_page = s.get(coa_url).text

# Extract the "New Account" form URLs from the Chart of Accounts page
bs_new_url = None
pnl_new_url = None
for m_link in re.finditer(r'href="(/(?:balance-sheet|profit-and-loss-statement)-account-form\?[^"]+)"', coa_page):
    link = m_link.group(1)
    if "balance-sheet-account-form" in link:
        bs_new_url = f"{MANAGER_URL}{link}"
    elif "profit-and-loss-statement-account-form" in link:
        pnl_new_url = f"{MANAGER_URL}{link}"

print(f"  BS account form URL: {'found' if bs_new_url else 'NOT FOUND'}")
print(f"  P&L account form URL: {'found' if pnl_new_url else 'NOT FOUND'}")

# Create accounts one at a time, re-fetching the COA page each time
# to get a fresh form URL (Manager.io v26 form URLs may be one-time tokens)
for name, acct_type in accounts_to_create:
    # Re-check if account already exists
    coa_page_now = s.get(coa_url).text
    if name in coa_page_now:
        print(f"  Account '{name}' already exists")
        continue
    # Extract FRESH form URL from the current COA page
    form_url = None
    target = "balance-sheet-account-form" if acct_type == "bs" else "profit-and-loss-statement-account-form"
    m_link = re.search(r'href="(/' + target + r'\?[^"]+)"', coa_page_now)
    if m_link:
        form_url = f"{MANAGER_URL}{m_link.group(1)}"
    if not form_url:
        print(f"  SKIP '{name}': no form URL for type {acct_type}")
        continue
    code = post_entity(s, form_url, {"Name": name})
    print(f"  Created account '{name}' (Type={acct_type}): HTTP {code}")
    time.sleep(0.5)

# -------------------------------------------------------------------
# Phase 2: Create customers and suppliers
# -------------------------------------------------------------------
print("\n--- Phase 2: Creating customers and suppliers ---")
cust_list_url = f"{MANAGER_URL}/customers?{biz_key}"
sup_list_url = f"{MANAGER_URL}/suppliers?{biz_key}"

customers_to_ensure = [
    ("Alfreds Futterkiste", None, None),
    ("Ernst Handel", None, None),
    ("Quick-Stop", "QS-001", "quickstop@example.com"),
    ("Save-a-Lot Markets", "SAL-001", "savelot@example.com"),
]

for name, code_str, email in customers_to_ensure:
    if entity_exists_http(s, cust_list_url, name):
        print(f"  Customer '{name}' already exists (HTTP)")
        continue
    form_url = f"{MANAGER_URL}/customer-form?{biz_key}"
    data = {"Name": name}
    if code_str:
        data["Code"] = code_str
    if email:
        data["Email"] = email
    code = post_entity(s, form_url, data)
    print(f"  Created customer '{name}': HTTP {code}")

# Suppliers
for name in ["Exotic Liquids", "City Services"]:
    if entity_exists_http(s, sup_list_url, name):
        print(f"  Supplier '{name}' already exists (HTTP)")
        continue
    form_url = f"{MANAGER_URL}/supplier-form?{biz_key}"
    code = post_entity(s, form_url, {"Name": name})
    print(f"  Created supplier '{name}': HTTP {code}")

# Cash on Hand bank account — always create since cached state may not have it
# Manager.io v26 uses 'bank-or-cash-account-form' endpoint (not 'bank-account-form')
bank_url = f"{MANAGER_URL}/bank-and-cash-accounts?{biz_key}"
bank_page = s.get(bank_url).text
if "Cash on Hand" not in bank_page:
    m_bank = re.search(r'href="(/bank-or-cash-account-form\?[^"]+)"[^>]*>[^<]*New', bank_page)
    if m_bank:
        form_url = f"{MANAGER_URL}{m_bank.group(1)}"
    else:
        form_url = f"{MANAGER_URL}/bank-or-cash-account-form?{biz_key}"
    code = post_entity(s, form_url, {"Name": "Cash on Hand"})
    print(f"  Created bank account 'Cash on Hand': HTTP {code}")
else:
    print(f"  Bank account 'Cash on Hand' already exists")

# Wait for Manager.io to flush data to SQLite
time.sleep(3)

# -------------------------------------------------------------------
# Phase 3: Read all UUIDs from SQLite
# -------------------------------------------------------------------
print("\n--- Phase 3: Reading UUIDs from database ---")
DB_PATH = find_db_path()  # Re-read in case it was updated

cust_uuids = {}
for name, _, _ in customers_to_ensure:
    uid = db_find_uuid(DB_PATH, name)
    cust_uuids[name] = uid
    status = uid[:12] + "..." if uid else "NOT IN DB"
    print(f"  Customer '{name}': {status}")

sup_uuids = {}
for name in ["Exotic Liquids", "City Services"]:
    uid = db_find_uuid(DB_PATH, name)
    sup_uuids[name] = uid
    status = uid[:12] + "..." if uid else "NOT IN DB"
    print(f"  Supplier '{name}': {status}")

cash_uuid = db_find_uuid(DB_PATH, "Cash on Hand")
print(f"  Cash on Hand: {cash_uuid[:12] + '...' if cash_uuid else 'NOT IN DB'}")

acct_uuids = {}
for name, _ in accounts_to_create:
    uid = db_find_uuid(DB_PATH, name)
    acct_uuids[name] = uid
acct_uuids["Bank charges"] = db_find_uuid(DB_PATH, "Bank charges")
print(f"  Account UUIDs found: {sum(1 for v in acct_uuids.values() if v)}/{len(acct_uuids)}")

# Check for missing critical UUIDs
missing = []
for name, uid in cust_uuids.items():
    if not uid:
        missing.append(f"Customer '{name}'")
if not cash_uuid:
    missing.append("Cash on Hand")
for name in ["Cost of Goods Sold", "Office Supplies"]:
    if not acct_uuids.get(name):
        missing.append(f"Account '{name}'")

if missing:
    print(f"\nWARNING: Missing UUIDs for: {', '.join(missing)}")
    print("Some invoices/payments may not be created correctly.")

# -------------------------------------------------------------------
# Phase 4: Create sales invoices
# -------------------------------------------------------------------
print("\n--- Phase 4: Creating sales invoices ---")
invoices = [
    ("INV-AF-001", "2025-01-15", "Alfreds Futterkiste", 3200.00, "Specialty tea and beverage supply"),
    ("INV-AF-002", "2025-02-10", "Alfreds Futterkiste", 1800.00, "Organic herbal tea collection"),
    ("INV-EH-001", "2025-01-25", "Ernst Handel", 1500.00, "Standard beverage assortment"),
    ("INV-EH-002", "2025-03-01", "Ernst Handel", 2200.00, "Premium olive oil shipment"),
    ("INV-QS-001", "2025-02-05", "Quick-Stop", 950.00, "Quick service beverage order"),
    ("INV-QS-002", "2025-02-28", "Quick-Stop", 1100.00, "Monthly snack and drink restock"),
    ("INV-SM-001", "2025-01-30", "Save-a-Lot Markets", 2400.00, "Bulk condiment supply"),
    ("INV-SM-002", "2025-03-15", "Save-a-Lot Markets", 1200.00, "Seasonal product order"),
]

si_page = s.get(f"{MANAGER_URL}/sales-invoices?{biz_key}").text
for ref, date, cust_name, amount, desc in invoices:
    if ref in si_page:
        print(f"  {ref} already exists")
        continue
    cust_uuid = cust_uuids.get(cust_name)
    form_url = f"{MANAGER_URL}/sales-invoice-form?{biz_key}"
    inv_data = {
        "IssueDate": date,
        "Reference": ref,
        "Lines": [{"LineDescription": desc, "Qty": 1.0, "SalesUnitPrice": amount}]
    }
    if cust_uuid:
        inv_data["Customer"] = cust_uuid
    code = post_entity(s, form_url, inv_data)
    linked = "with customer" if cust_uuid else "NO customer link"
    print(f"  Created {ref} ({cust_name}, ${amount}, {linked}): HTTP {code}")

# -------------------------------------------------------------------
# Phase 5: Create purchase invoices
# -------------------------------------------------------------------
print("\n--- Phase 5: Creating purchase invoices ---")
cogs_uuid = acct_uuids.get("Cost of Goods Sold")
exotic_uuid = sup_uuids.get("Exotic Liquids")

pi_page = s.get(f"{MANAGER_URL}/purchase-invoices?{biz_key}").text
for ref, date, amount, desc in [
    ("PO-EL-001", "2025-01-10", 2750.00, "January beverage wholesale"),
    ("PO-EL-002", "2025-02-20", 1800.00, "February beverage wholesale"),
    ("PO-EL-003", "2025-03-10", 2100.00, "March beverage wholesale"),
]:
    if ref in pi_page:
        print(f"  {ref} already exists")
        continue
    form_url = f"{MANAGER_URL}/purchase-invoice-form?{biz_key}"
    po_data = {
        "IssueDate": date,
        "Reference": ref,
        "Lines": [{"LineDescription": desc, "Qty": 1.0, "PurchaseUnitPrice": amount}]
    }
    if exotic_uuid:
        po_data["Supplier"] = exotic_uuid
    if cogs_uuid:
        po_data["Lines"][0]["Account"] = cogs_uuid
    code = post_entity(s, form_url, po_data)
    print(f"  Created {ref} (${amount}): HTTP {code}")

# -------------------------------------------------------------------
# Phase 6: Create the miscoded City Services payment
# -------------------------------------------------------------------
print("\n--- Phase 6: Creating miscoded payment ---")
office_supplies_uuid = acct_uuids.get("Office Supplies")
pay_page = s.get(f"{MANAGER_URL}/payments?{biz_key}").text

if "City Services" not in pay_page:
    if cash_uuid:
        # Get the NEW Payment URL from the payments list page
        m_pay_form = re.search(r'href="(/payment-form\?[^"]+)"', pay_page)
        if m_pay_form:
            pay_form_url = f"{MANAGER_URL}{m_pay_form.group(1)}"
        else:
            pay_form_url = f"{MANAGER_URL}/payment-form?{biz_key}"
        # Payee=0 means "Other/Contact", Contact holds the name string
        payment_data = {
            "Date": "2025-03-05",
            "Payee": 0,
            "Contact": "City Services",
            "PaidFrom": cash_uuid,
            "Lines": [
                {
                    "Amount": 1500.00,
                    "LineDescription": "Quarterly facility maintenance"
                }
            ]
        }
        if office_supplies_uuid:
            payment_data["Lines"][0]["Account"] = office_supplies_uuid
        code = post_entity(s, pay_form_url, payment_data)
        print(f"  Created City Services payment ($1,500): HTTP {code}")
    else:
        print(f"  WARNING: Cannot create payment - no Cash on Hand UUID")
else:
    print(f"  City Services payment already exists")

# -------------------------------------------------------------------
# Phase 7: Record baselines for anti-gaming
# -------------------------------------------------------------------
print("\n--- Phase 7: Recording baselines ---")
time.sleep(1)

pay_page = s.get(f"{MANAGER_URL}/payments?{biz_key}").text
payment_count = pay_page.count(">Edit<")
with open("/tmp/manager_task_payment_count", "w") as f:
    f.write(str(payment_count))
print(f"  Baseline payment count: {payment_count}")

je_page = s.get(f"{MANAGER_URL}/journal-entries?{biz_key}").text
je_count = je_page.count(">Edit<")
with open("/tmp/manager_task_je_count", "w") as f:
    f.write(str(je_count))
print(f"  Baseline JE count: {je_count}")

# -------------------------------------------------------------------
# Final verification
# -------------------------------------------------------------------
print("\n--- Final verification ---")
si_page = s.get(f"{MANAGER_URL}/sales-invoices?{biz_key}").text
for ref in ["INV-AF-001", "INV-EH-001", "INV-QS-001", "INV-SM-001"]:
    print(f"  {ref}: {'OK' if ref in si_page else 'MISSING'}")

pi_page = s.get(f"{MANAGER_URL}/purchase-invoices?{biz_key}").text
print(f"  Purchase invoices: {'OK' if 'PO-EL' in pi_page else 'MISSING'}")

pay_page = s.get(f"{MANAGER_URL}/payments?{biz_key}").text
print(f"  City Services payment: {'OK' if 'City Services' in pay_page else 'MISSING'}")

print("\nSetup complete.")
PYEOF

# Take initial screenshot
take_screenshot /tmp/quarter_end_close_start.png

# Open Manager at Summary
echo "Opening Manager.io Summary page..."
open_manager_at "summary"

echo ""
echo "=== quarter_end_close task setup complete ==="
