# Manager.io Environment — Evidence Documentation

Date verified: 2026-02-20
Environment: `benchmarks/environments/manager_env`
VM: Ubuntu 22.04, Docker, Manager.io Server Edition v26.2.13.3181

---

## Checklist Verification

### 1. Installation succeeds (pre_start / post_start hooks)

**Docker container running and healthy:**
```
NAMES            IMAGE                                  STATUS                 PORTS
manager-server   ghcr.io/aliyusuf95/manager.io:latest   Up 2 hours (healthy)   0.0.0.0:8080->8080/tcp
```

**Manager.io HTTP response (port 8080):**
```
< HTTP/1.1 302 Found
< Location: /login
```
(Redirect to /login confirms the app is running and responding correctly)

**Business data file on disk:**
```
/data/00000000000000000000000000000000.manager   ← admin config
/data/Northwind Traders.manager                  ← business data
```

---

### 2. Manager.io accessible via browser

The `navigate_manager.py` script opens Firefox at `http://localhost:8080/`, logs in
as `administrator` (no password), and selects the Northwind Traders business.

**See:** `screenshot_summary_page.png` — Summary page visible in Firefox after login.

---

### 3. Pre-task setup works for all 10 tasks

Each task's `setup_task.sh` calls `open_manager_at <module> [new]` which invokes
`navigate_manager.py` with xdotool to click through the UI.

#### All 10 tasks verified (summary):
| Task | Module navigated | Form opened | Screenshot |
|------|-----------------|-------------|------------|
| create_customer | customers | New Customer form | screenshot_new_customer_form.png |
| create_sales_invoice | sales_invoices | New Sales Invoice form | screenshot_new_sales_invoice_form.png |
| record_receipt | receipts | New Receipt form | screenshot_new_receipt_form.png |
| create_supplier | suppliers | New Supplier form | screenshot_new_supplier_form.png |
| create_purchase_invoice | purchase_invoices | New Purchase Invoice form | screenshot_new_purchase_invoice_form.png |
| add_inventory_item | inventory | New Inventory Item form | screenshot_new_inventory_item_form.png |
| create_journal_entry | journal_entries | New Journal Entry form | screenshot_new_journal_entry_form.png |
| view_balance_sheet | reports | Reports page | screenshot_reports_page.png |
| create_credit_note | credit_notes | New Credit Note form | screenshot_new_credit_note_form.png |
| generate_aged_receivables | reports | Reports page | screenshot_reports_page.png |

---

### 4. Seed data present: Northwind Traders

**Customers (2):**
- Alfreds Futterkiste
- Ernst Handel

**Supplier (1):**
- Exotic Liquids

**Bank Account (1):**
- Cash on Hand

**Modules enabled (12):**
Bank accounts, Receipts, Payments, Customers, Sales Invoices, Credit Notes,
Suppliers, Purchase Invoices, Debit Notes, Inventory, Journal Entries, Reports

---

### 5. Screenshots (10 total — all tasks covered)

| File | Description |
|------|-------------|
| `screenshot_summary_page.png` | Northwind Traders Summary page after login |
| `screenshot_new_customer_form.png` | New Customer form (blank) — fields: Name, Code, Credit Limit, Address, Email |
| `screenshot_new_sales_invoice_form.png` | New Sales Invoice form with date, customer, line items (Account-based) |
| `screenshot_new_receipt_form.png` | New Receipt form — fields: Date, Paid By (Contact), Received In (Account), Amount |
| `screenshot_new_supplier_form.png` | New Supplier form — fields: Name, Code, Credit Limit, Address, Email |
| `screenshot_new_purchase_invoice_form.png` | New Purchase Invoice form |
| `screenshot_new_inventory_item_form.png` | New Inventory Item form (blank) |
| `screenshot_new_journal_entry_form.png` | New Journal Entry form — Debit/Credit rows with Account dropdown |
| `screenshot_new_credit_note_form.png` | New Credit Note form — Customer, Sales Invoice, line items |
| `screenshot_reports_page.png` | Reports module with all report categories visible |

---

### 6. Clean env.reset() with use_cache=False (full provisioning)

See `clean_env_reset_log.txt` for the full log. Key output:
```
Starting clean env.reset() - this runs all hooks from scratch...
Start time: 2026-02-20 14:25:35
[QemuApptainer] VNC password set (port 5917)
[QemuApptainer] SSH available!
[QemuApptainer] Copying benchmarks/environments/manager_env/scripts -> /workspace/scripts
[QemuApptainer] Copying benchmarks/environments/manager_env/config -> /workspace/config
[QemuApptainer] Copying benchmarks/environments/manager_env/tasks -> /workspace/tasks
[QemuApptainer] Desktop ready after 0.1s
[VNC] Connected to QEMU (1920x1080)
[QemuApptainer] VM ready! Resolution: (1920, 1080)
[gym-anything] Running pre_start hook...
[gym-anything] Running post_start hook...
Profiling time for env setup: 163.8s
Reset complete at 2026-02-20 14:28:20
Docker containers:
manager-server Up 25 seconds (healthy)
CLEAN RESET SUCCEEDED
```

**Total provisioning time**: 163.8 seconds (~2.7 minutes) from bare VM to working Manager.io

---

### 7. Key technical notes

- **Docker Compose v2**: Uses `docker compose` (plugin syntax), not `docker-compose`
- **Manager.io data volume**: `/data` in container, persists between sessions
- **Login**: Single-step (username only, no password) — enter `administrator` then click Next
- **Firefox snap quirks**: Lock files at `~/snap/firefox/common/.mozilla/...` (not `~/.mozilla/...`)
- **navigate_manager.py**: Handles Restore Session dialog, lock file cleanup, systemd scope reset
- **Coordinate scale**: xdotool uses 1920×1080 (1.5× the 1280×720 visual_grounding coords)
- **Sidebar x-coordinate**: All sidebar items at x=154 (720p) = x=231 (1080p)

### 8. Audit fixes applied (2026-02-20)

Following an independent audit, these issues were corrected:

**SEVERE fixes:**
- `create_customer/task.json`: Removed non-existent "Contact Person" and "Phone" fields; added Code (BRT-001) and Credit Limit (25000) which ARE actual form fields
- `create_supplier/task.json`: Same — removed Contact Person/Phone; added Code (PIS-001)
- `create_sales_invoice/task.json`: Replaced "Chai/Chang inventory items" (non-existent) with account-based line items using Description + Account + Qty + Unit Price

**SIGNIFICANT fixes:**
- `record_receipt/task.json`: Removed "link invoice if available" hedge (no invoices exist); rewrote with actual form field names: "Paid By > Contact", "Received In > Account: Cash on Hand", line item Amount 440.00
- `view_balance_sheet/task.json`: Added clarification that values may be 0.00 in a fresh business — this is expected
- `generate_aged_receivables/task.json`: Clarified that report may be empty in fresh business; reporting 0.00 is a valid result

**MINOR fixes:**
- `create_journal_entry/task.json`: Replaced "Prepaid Expenses (or equivalent)" with confirmed-existing accounts: "Accounting fees" (debit) and "Retained earnings" (credit)
  - Note: "Cash on Hand" bank account does NOT appear in journal entry Account dropdown; it's a bank module account only

**Evidence:**
- All 5 previously missing screenshots captured and added to evidence/
