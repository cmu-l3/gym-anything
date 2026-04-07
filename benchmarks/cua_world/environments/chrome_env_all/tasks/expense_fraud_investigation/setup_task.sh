#!/bin/bash
set -euo pipefail

###############################################################################
# Task: expense_fraud_investigation — Q4 Expense Fraud Investigation
# Sets up a localhost expense management web app with planted fraud patterns.
###############################################################################

# ── 0. Clean stale outputs BEFORE recording timestamp ─────────────────────
rm -f /tmp/task_result.json /tmp/task_start_time.txt /tmp/task_end_time.txt
rm -f /tmp/task_initial.png /tmp/task_final.png
rm -f /home/ga/Documents/Fraud_Investigation/report.txt 2>/dev/null || true

# ── 1. Record start timestamp ────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Prepare directories ───────────────────────────────────────────────
mkdir -p /home/ga/Documents/Fraud_Investigation
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Documents

# ── 3. Generate web application (Python — all 4 HTML pages) ──────────────
SERVER_DIR="/tmp/expense_system"
rm -rf "$SERVER_DIR"
mkdir -p "$SERVER_DIR"

python3 << 'PYEOF'
import json, os

SD = "/tmp/expense_system"

# ═══════════════════════════════════════════════════════════════════════════
# DATA
# ═══════════════════════════════════════════════════════════════════════════

transactions = [
    {"id":"TXN-001","emp":"Sarah Chen","dept":"Engineering","date":"2025-10-02","vendor":"Delta Airlines","amount":387.00,"cat":"Travel","project":"PRJ-002","desc":"Flight SFO-ORD for client meeting","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-002","emp":"Marcus Johnson","dept":"Sales","date":"2025-10-03","vendor":"Hilton Hotels","amount":225.00,"cat":"Lodging","project":"PRJ-004","desc":"Hotel for regional trade show","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-003","emp":"Priya Patel","dept":"Marketing","date":"2025-10-03","vendor":"Uber","amount":42.50,"cat":"Transportation","project":"PRJ-001","desc":"Airport to downtown office","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-004","emp":"James O'Brien","dept":"Executive","date":"2025-10-04","vendor":"Starbucks","amount":18.75,"cat":"Dining","project":"PRJ-006","desc":"Coffee meeting with VP Sales","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-005","emp":"Maria Rodriguez","dept":"Operations","date":"2025-10-04","vendor":"Staples","amount":67.30,"cat":"Office Supplies","project":"PRJ-012","desc":"Printer paper and toner cartridges","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-006","emp":"David Kim","dept":"Product","date":"2025-10-05","vendor":"Adobe","amount":54.99,"cat":"Software","project":"PRJ-011","desc":"Stock photo license - monthly","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-007","emp":"Lisa Thompson","dept":"HR","date":"2025-10-07","vendor":"Panera Bread","amount":32.40,"cat":"Dining","project":"PRJ-013","desc":"Lunch with engineering candidate","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-008","emp":"Marcus Johnson","dept":"Sales","date":"2025-10-08","vendor":"Pacific Coast Consulting","amount":3200.00,"cat":"Consulting","project":"PRJ-004","desc":"Strategic market analysis  - West region","receipt":True,"approval":"VP Approved - R. Hayes"},
    {"id":"TXN-009","emp":"Sarah Chen","dept":"Engineering","date":"2025-10-09","vendor":"Amazon Business","amount":89.99,"cat":"Office Supplies","project":"PRJ-002","desc":"USB-C docking station","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-010","emp":"Priya Patel","dept":"Marketing","date":"2025-10-10","vendor":"Google Cloud","amount":175.00,"cat":"Software","project":"PRJ-001","desc":"Ad platform credits - October","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-011","emp":"James O'Brien","dept":"Executive","date":"2025-10-11","vendor":"Delta Airlines","amount":512.00,"cat":"Travel","project":"PRJ-006","desc":"Flight NYC-LAX for board meeting","receipt":True,"approval":"Manager Approved - K. Nash"},
    {"id":"TXN-012","emp":"Robert Mitchell","dept":"Finance","date":"2025-10-12","vendor":"Office Depot","amount":43.25,"cat":"Office Supplies","project":"PRJ-010","desc":"Filing supplies and binders","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-013","emp":"Maria Rodriguez","dept":"Operations","date":"2025-10-14","vendor":"FedEx","amount":28.90,"cat":"Shipping","project":"PRJ-012","desc":"Overnight shipment to client site","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-014","emp":"Marcus Johnson","dept":"Sales","date":"2025-10-17","vendor":"The Capital Grille","amount":186.50,"cat":"Dining","project":"PRJ-004","desc":"Client dinner - Acme Corp deal  ","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-015","emp":"James O'Brien","dept":"Executive","date":"2025-10-17","vendor":"The Capital Grille","amount":186.50,"cat":"Dining","project":"PRJ-006","desc":"Dinner with prospective clients","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-016","emp":"Sarah Chen","dept":"Engineering","date":"2025-10-18","vendor":"Zoom","amount":14.99,"cat":"Software","project":"PRJ-002","desc":"Video conferencing monthly subscription","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-017","emp":"Lisa Thompson","dept":"HR","date":"2025-10-18","vendor":"FedEx Office","amount":56.80,"cat":"Shipping","project":"PRJ-013","desc":"Printed onboarding materials - 50 sets","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-018","emp":"David Kim","dept":"Product","date":"2025-10-19","vendor":"Microsoft","amount":299.00,"cat":"Software","project":"PRJ-011","desc":"Office 365 annual license renewal","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-019","emp":"James O'Brien","dept":"Executive","date":"2025-10-22","vendor":"Sterling Associates","amount":4500.00,"cat":"Consulting","project":"PRJ-006","desc":"Executive advisory  services - Q4 strategy","receipt":True,"approval":"SVP Approved - C. Wong"},
    {"id":"TXN-020","emp":"Robert Mitchell","dept":"Finance","date":"2025-10-22","vendor":"Uber","amount":31.50,"cat":"Transportation","project":"PRJ-010","desc":"Transport to audit site","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-021","emp":"Marcus Johnson","dept":"Sales","date":"2025-10-23","vendor":"Southwest Airlines","amount":198.00,"cat":"Travel","project":"PRJ-004","desc":"Flight to regional sales office","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-022","emp":"Priya Patel","dept":"Marketing","date":"2025-10-28","vendor":"Starbucks","amount":34.50,"cat":"Dining","project":"PRJ-099","desc":"Team coffee run - campaign kickoff","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-023","emp":"Sarah Chen","dept":"Engineering","date":"2025-10-28","vendor":"AWS","amount":847.00,"cat":"Software","project":"PRJ-008","desc":"Cloud hosting - monthly usage","receipt":True,"approval":"Manager Approved - D. Lin"},
    {"id":"TXN-024","emp":"Maria Rodriguez","dept":"Operations","date":"2025-10-29","vendor":"Enterprise Rent-A-Car","amount":88.50,"cat":"Transportation","project":"PRJ-012","desc":"Car rental for warehouse site visit","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-025","emp":"Sarah Chen","dept":"Engineering","date":"2025-11-03","vendor":"Marriott Hotels","amount":245.00,"cat":"Lodging","project":"PRJ-005","desc":"Conference hotel - 1 night","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-026","emp":"Robert Mitchell","dept":"Finance","date":"2025-11-03","vendor":"Marriott Hotels","amount":245.00,"cat":"Lodging","project":"PRJ-010","desc":"Hotel for compliance seminar","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-027","emp":"James O'Brien","dept":"Executive","date":"2025-11-01","vendor":"The Capital Grille","amount":312.00,"cat":"Dining","project":"PRJ-003","desc":"Client entertainment dinner - Q4 planning","receipt":True,"approval":"Manager Approved - K. Nash"},
    {"id":"TXN-028","emp":"Lisa Thompson","dept":"HR","date":"2025-11-04","vendor":"Chipotle","amount":28.50,"cat":"Dining","project":"PRJ-013","desc":"Working lunch with benefits team","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-029","emp":"Priya Patel","dept":"Marketing","date":"2025-11-05","vendor":"Salesforce","amount":150.00,"cat":"Software","project":"PRJ-001","desc":"CRM platform - monthly license","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-030","emp":"David Kim","dept":"Product","date":"2025-11-06","vendor":"Slack","amount":72.00,"cat":"Software","project":"PRJ-011","desc":"Team collaboration plan upgrade","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-031","emp":"Marcus Johnson","dept":"Sales","date":"2025-11-08","vendor":"Pacific Coast Consulting","amount":2800.00,"cat":"Consulting","project":"PRJ-014","desc":"Regional market assessment  study","receipt":True,"approval":"VP Approved - R. Hayes"},
    {"id":"TXN-032","emp":"Robert Mitchell","dept":"Finance","date":"2025-11-08","vendor":"Deloitte","amount":1500.00,"cat":"Professional Services","project":"PRJ-010","desc":"External audit consultation","receipt":True,"approval":"Manager Approved - S. Grant"},
    {"id":"TXN-033","emp":"Priya Patel","dept":"Marketing","date":"2025-11-12","vendor":"Uber","amount":67.30,"cat":"Transportation","project":"PRJ-001","desc":"Airport transfer for marketing conference","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-034","emp":"David Kim","dept":"Product","date":"2025-11-12","vendor":"Uber","amount":67.30,"cat":"Transportation","project":"PRJ-006","desc":"Airport shuttle to product conference","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-035","emp":"Sarah Chen","dept":"Engineering","date":"2025-11-13","vendor":"CDW","amount":124.50,"cat":"Office Supplies","project":"PRJ-008","desc":"Network cables and patch panel","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-036","emp":"James O'Brien","dept":"Executive","date":"2025-11-14","vendor":"American Airlines","amount":445.00,"cat":"Travel","project":"PRJ-006","desc":"Flight to partner meeting in Dallas","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-037","emp":"Maria Rodriguez","dept":"Operations","date":"2025-11-14","vendor":"UPS","amount":19.75,"cat":"Shipping","project":"PRJ-012","desc":"Package return to warehouse","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-038","emp":"David Kim","dept":"Product","date":"2025-11-15","vendor":"Adobe","amount":599.00,"cat":"Software","project":"PRJ-087","desc":"Creative Suite annual license renewal","receipt":True,"approval":"Manager Approved - J. Torres"},
    {"id":"TXN-039","emp":"Marcus Johnson","dept":"Sales","date":"2025-11-16","vendor":"Lyft","amount":54.00,"cat":"Transportation","project":"PRJ-004","desc":"Transport to client site in suburbs","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-040","emp":"Robert Mitchell","dept":"Finance","date":"2025-11-17","vendor":"Starbucks","amount":22.10,"cat":"Dining","project":"PRJ-010","desc":"Coffee with department head","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-041","emp":"Lisa Thompson","dept":"HR","date":"2025-11-18","vendor":"Amazon Business","amount":38.99,"cat":"Office Supplies","project":"PRJ-013","desc":"Desk organizer bins for new hires","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-042","emp":"Sarah Chen","dept":"Engineering","date":"2025-11-19","vendor":"Sterling Associates","amount":1200.00,"cat":"Consulting","project":"PRJ-008","desc":"Technical infrastructure consulting review","receipt":True,"approval":"Manager Approved - D. Lin"},
    {"id":"TXN-043","emp":"Priya Patel","dept":"Marketing","date":"2025-11-20","vendor":"Google Cloud","amount":225.00,"cat":"Software","project":"PRJ-001","desc":"Ad platform credits - November","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-044","emp":"David Kim","dept":"Product","date":"2025-11-21","vendor":"AWS","amount":1247.00,"cat":"Software","project":"PRJ-007","desc":"Cloud hosting - quarterly compute charges","receipt":True,"approval":"Manager Approved - J. Torres"},
    {"id":"TXN-045","emp":"Marcus Johnson","dept":"Sales","date":"2025-11-22","vendor":"Hilton Hotels","amount":210.00,"cat":"Lodging","project":"PRJ-004","desc":"Hotel for client visit","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-046","emp":"James O'Brien","dept":"Executive","date":"2025-11-22","vendor":"Hertz","amount":95.00,"cat":"Transportation","project":"PRJ-006","desc":"Car rental for offsite meeting","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-047","emp":"Maria Rodriguez","dept":"Operations","date":"2025-11-24","vendor":"Staples","amount":41.20,"cat":"Office Supplies","project":"PRJ-012","desc":"Shipping supplies and tape","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-048","emp":"Robert Mitchell","dept":"Finance","date":"2025-11-25","vendor":"PwC","amount":2200.00,"cat":"Professional Services","project":"PRJ-010","desc":"Tax advisory and compliance services","receipt":True,"approval":"VP Approved - M. Chen"},
    {"id":"TXN-049","emp":"Sarah Chen","dept":"Engineering","date":"2025-11-26","vendor":"Zoom","amount":14.99,"cat":"Software","project":"PRJ-002","desc":"Video conferencing - monthly renewal","receipt":True,"approval":"Auto-approved"},
    {"id":"TXN-050","emp":"Marcus Johnson","dept":"Sales","date":"2025-11-27","vendor":"Ruth's Chris Steak House","amount":142.75,"cat":"Dining","project":"PRJ-004","desc":"Team celebration dinner - Q4 milestone","receipt":True,"approval":"Auto-approved"},
]

vendors_by_cat = {
    "Airlines & Travel": ["Delta Airlines","United Airlines","American Airlines","Southwest Airlines"],
    "Hotels & Lodging": ["Marriott Hotels","Hilton Hotels","Hyatt Hotels"],
    "Ground Transportation": ["Uber","Lyft","Enterprise Rent-A-Car","Hertz","National Car Rental"],
    "Dining & Catering": ["The Capital Grille","Ruth's Chris Steak House","Olive Garden","Panera Bread","Starbucks","Chipotle","Nobu"],
    "Office Supplies": ["Staples","Office Depot","Amazon Business","CDW"],
    "Software & Cloud": ["Microsoft","Adobe","Salesforce","AWS","Google Cloud","Zoom","Slack"],
    "Professional Services": ["Deloitte","McKinsey & Company","Accenture","Boston Consulting Group","PwC","KPMG","Ernst & Young"],
    "Shipping & Logistics": ["FedEx","UPS","FedEx Office"],
}

projects = [
    {"code":"PRJ-001","name":"Q4 Marketing Campaign","dept":"Marketing","budget":45000,"status":"Active"},
    {"code":"PRJ-002","name":"Customer Portal Redesign","dept":"Engineering","budget":120000,"status":"Active"},
    {"code":"PRJ-003","name":"Server Infrastructure Upgrade","dept":"IT Operations","budget":85000,"status":"Active"},
    {"code":"PRJ-004","name":"Annual Sales Conference","dept":"Sales","budget":60000,"status":"Active"},
    {"code":"PRJ-005","name":"Employee Training Program","dept":"HR","budget":35000,"status":"Active"},
    {"code":"PRJ-006","name":"Product Launch - Alpha Series","dept":"Executive","budget":200000,"status":"Active"},
    {"code":"PRJ-007","name":"Office Renovation Phase 2","dept":"Facilities","budget":150000,"status":"Active"},
    {"code":"PRJ-008","name":"Data Analytics Platform","dept":"Engineering","budget":95000,"status":"Active"},
    {"code":"PRJ-009","name":"Client Onboarding Automation","dept":"Operations","budget":55000,"status":"Active"},
    {"code":"PRJ-010","name":"Security Compliance Audit","dept":"Finance","budget":40000,"status":"Active"},
    {"code":"PRJ-011","name":"Mobile App Development","dept":"Product","budget":110000,"status":"Active"},
    {"code":"PRJ-012","name":"Supply Chain Optimization","dept":"Operations","budget":70000,"status":"Active"},
    {"code":"PRJ-013","name":"HR System Migration","dept":"HR","budget":48000,"status":"Active"},
    {"code":"PRJ-014","name":"Regional Expansion Research","dept":"Sales","budget":30000,"status":"Active"},
    {"code":"PRJ-015","name":"Sustainability Initiative","dept":"Executive","budget":25000,"status":"Active"},
]

# ═══════════════════════════════════════════════════════════════════════════
# SHARED CSS
# ═══════════════════════════════════════════════════════════════════════════

CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f0f2f5; color: #1a1a2e; }
nav { background: #1a237e; padding: 0 32px; display: flex; align-items: center; height: 56px; }
nav .brand { color: #fff; font-size: 17px; font-weight: 700; margin-right: 40px; letter-spacing: -0.3px; }
nav a { color: #9fa8da; text-decoration: none; font-size: 14px; padding: 16px 14px; transition: color 0.15s; }
nav a:hover, nav a.active { color: #fff; border-bottom: 2px solid #fff; }
.container { max-width: 1280px; margin: 28px auto; padding: 0 32px; }
h1 { font-size: 22px; margin-bottom: 16px; color: #1a237e; }
h2 { font-size: 17px; margin: 20px 0 10px; color: #37474f; }
.card { background: #fff; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); padding: 20px 24px; margin-bottom: 20px; }
table { width: 100%; border-collapse: collapse; }
th { background: #e8eaf6; padding: 10px 14px; text-align: left; font-size: 13px; font-weight: 600; color: #37474f; white-space: nowrap; }
td { padding: 9px 14px; border-bottom: 1px solid #e8e8e8; font-size: 14px; }
tr.data-row { cursor: pointer; transition: background 0.12s; }
tr.data-row:hover { background: #e3f2fd; }
tr.data-row:nth-child(4n+1) { background: #fafbfc; }
tr.data-row:nth-child(4n+1):hover { background: #e3f2fd; }
.detail-cell { padding: 12px 24px 16px; background: #f5f6fa; font-size: 13px; line-height: 1.7; border-bottom: 2px solid #c5cae9; }
.detail-cell b { color: #37474f; }
.pagination { display: flex; align-items: center; gap: 12px; margin-top: 16px; justify-content: center; }
.pagination button { padding: 7px 18px; border: 1px solid #c5cae9; background: #fff; border-radius: 4px; cursor: pointer; font-size: 13px; color: #1a237e; }
.pagination button:hover { background: #e8eaf6; }
.pagination button:disabled { opacity: 0.4; cursor: default; }
.pagination span { font-size: 13px; color: #666; }
.stats { display: flex; gap: 20px; flex-wrap: wrap; margin-bottom: 24px; }
.stat-card { background: #fff; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); padding: 18px 24px; flex: 1; min-width: 180px; }
.stat-card .label { font-size: 12px; color: #78909c; text-transform: uppercase; letter-spacing: 0.5px; }
.stat-card .value { font-size: 26px; font-weight: 700; color: #1a237e; margin-top: 4px; }
.tag { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 12px; font-weight: 500; }
.tag-active { background: #e8f5e9; color: #2e7d32; }
"""

def nav_html(active):
    items = [("index.html","Dashboard"),("ledger.html","Expense Ledger"),("vendors.html","Approved Vendors"),("projects.html","Project Directory")]
    links = ""
    for href, label in items:
        cls = ' class="active"' if label == active else ""
        links += f'<a href="{href}"{cls}>{label}</a> '
    return f'<nav><span class="brand">ExpenseTrack Pro</span>{links}</nav>'

# ═══════════════════════════════════════════════════════════════════════════
# index.html — Dashboard
# ═══════════════════════════════════════════════════════════════════════════
total_amount = sum(t["amount"] for t in transactions)
emps = sorted(set(t["emp"] for t in transactions))

with open(f"{SD}/index.html", "w") as f:
    f.write(f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>ExpenseTrack Pro - Dashboard</title>
<style>{CSS}</style></head>
<body>
{nav_html("Dashboard")}
<div class="container">
<h1>Q4 2025 Expense Dashboard</h1>
<div class="stats">
  <div class="stat-card"><div class="label">Total Transactions</div><div class="value">{len(transactions)}</div></div>
  <div class="stat-card"><div class="label">Total Amount</div><div class="value">${total_amount:,.2f}</div></div>
  <div class="stat-card"><div class="label">Employees</div><div class="value">{len(emps)}</div></div>
  <div class="stat-card"><div class="label">Date Range</div><div class="value" style="font-size:16px">Oct 2 - Nov 27, 2025</div></div>
</div>
<div class="card">
<h2>Quick Links</h2>
<ul style="margin:12px 0 0 20px;line-height:2">
  <li><a href="ledger.html">Expense Ledger</a> — Full transaction listing with details</li>
  <li><a href="vendors.html">Approved Vendor Directory</a> — Company-authorized vendors by category</li>
  <li><a href="projects.html">Project Directory</a> — Active project codes and budgets</li>
</ul>
</div>
<div class="card">
<h2>Employees</h2>
<table><tr><th>Name</th><th>Department</th><th>Transactions</th><th>Total Amount</th></tr>""")
    for emp in emps:
        emp_txns = [t for t in transactions if t["emp"] == emp]
        dept = emp_txns[0]["dept"]
        total = sum(t["amount"] for t in emp_txns)
        f.write(f'<tr><td>{emp}</td><td>{dept}</td><td>{len(emp_txns)}</td><td>${total:,.2f}</td></tr>\n')
    f.write("</table></div></div></body></html>")

# ═══════════════════════════════════════════════════════════════════════════
# ledger.html — Expense Ledger (paginated, click-to-expand details)
# ═══════════════════════════════════════════════════════════════════════════
txn_json = json.dumps(transactions)

# Build ledger page using string concatenation to avoid f-string escaping issues with JS
ledger_head = f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>ExpenseTrack Pro - Expense Ledger</title>
<style>{CSS}
.click-hint {{ font-size: 12px; color: #90a4ae; margin-bottom: 12px; font-style: italic; }}
</style></head>
<body>
{nav_html("Expense Ledger")}
<div class="container">
<h1>Expense Ledger — Q4 2025</h1>
<p class="click-hint">Click any row to view transaction details including project code and description.</p>
<div class="card" style="padding:0;overflow:hidden;">
<table>
<thead><tr><th>ID</th><th>Employee</th><th>Department</th><th>Date</th><th>Vendor</th><th>Amount</th><th>Category</th></tr></thead>
<tbody id="tbody"></tbody>
</table>
</div>
<div class="pagination">
<button id="btnPrev" onclick="prevPage()">Previous</button>
<span id="pageInfo"></span>
<button id="btnNext" onclick="nextPage()">Next</button>
</div>
</div>
<script>
"""

# JavaScript — written as a plain Python string (no f-string to avoid {{ }} issues)
ledger_js = """
const txns = __TXN_DATA__;
const perPage = 10;
let currentPage = 0;
let openDetail = -1;

function fmtMoney(n) { return '$' + n.toFixed(2).replace(/\\B(?=(\\d{3})+(?!\\d))/g, ','); }

function render() {
    const totalPages = Math.ceil(txns.length / perPage);
    const start = currentPage * perPage;
    const page = txns.slice(start, start + perPage);
    let html = '';
    page.forEach(function(t, i) {
        const idx = start + i;
        const sel = (idx === openDetail) ? 'background:#e3f2fd;' : '';
        html += '<tr class="data-row" style="' + sel + '" onclick="toggleDetail(' + idx + ')">';
        html += '<td>' + t.id + '</td>';
        html += '<td>' + t.emp + '</td>';
        html += '<td>' + t.dept + '</td>';
        html += '<td>' + t.date + '</td>';
        html += '<td>' + t.vendor + '</td>';
        html += '<td style="text-align:right;font-weight:500">' + fmtMoney(t.amount) + '</td>';
        html += '<td>' + t.cat + '</td>';
        html += '</tr>';
        if (idx === openDetail) {
            html += '<tr><td colspan="7" class="detail-cell">';
            html += '<b>Project Code:</b> ' + t.project + ' &nbsp;&bull;&nbsp; ';
            html += '<b>Description:</b> ' + t.desc + ' &nbsp;&bull;&nbsp; ';
            html += '<b>Receipt:</b> ' + (t.receipt ? 'Yes' : 'No') + ' &nbsp;&bull;&nbsp; ';
            html += '<b>Approval:</b> ' + t.approval;
            html += '</td></tr>';
        }
    });
    document.getElementById('tbody').innerHTML = html;
    document.getElementById('pageInfo').textContent = 'Page ' + (currentPage + 1) + ' of ' + totalPages;
    document.getElementById('btnPrev').disabled = (currentPage === 0);
    document.getElementById('btnNext').disabled = (currentPage >= totalPages - 1);
}

function toggleDetail(idx) {
    openDetail = (openDetail === idx) ? -1 : idx;
    render();
}

function nextPage() {
    if ((currentPage + 1) * perPage < txns.length) { currentPage++; openDetail = -1; render(); }
}

function prevPage() {
    if (currentPage > 0) { currentPage--; openDetail = -1; render(); }
}

window.onload = render;
"""

ledger_js = ledger_js.replace("__TXN_DATA__", txn_json)

with open(f"{SD}/ledger.html", "w") as f:
    f.write(ledger_head)
    f.write(ledger_js)
    f.write("\n</script></body></html>")

# ═══════════════════════════════════════════════════════════════════════════
# vendors.html — Approved Vendor Directory
# ═══════════════════════════════════════════════════════════════════════════
with open(f"{SD}/vendors.html", "w") as f:
    f.write(f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>ExpenseTrack Pro - Approved Vendors</title>
<style>{CSS}</style></head>
<body>
{nav_html("Approved Vendors")}
<div class="container">
<h1>Approved Vendor Directory</h1>
<p style="color:#607d8b;margin-bottom:20px;font-size:14px;">Only vendors listed below are authorized for expense reimbursement. Submissions to unlisted vendors require separate justification and VP-level approval.</p>
""")
    for cat, vlist in vendors_by_cat.items():
        f.write(f'<div class="card"><h2>{cat}</h2><table><tr><th style="width:40px">#</th><th>Vendor Name</th><th>Status</th></tr>\n')
        for j, v in enumerate(vlist, 1):
            f.write(f'<tr><td>{j}</td><td>{v}</td><td><span class="tag tag-active">Approved</span></td></tr>\n')
        f.write("</table></div>\n")
    f.write("</div></body></html>")

# ═══════════════════════════════════════════════════════════════════════════
# projects.html — Project Directory
# ═══════════════════════════════════════════════════════════════════════════
with open(f"{SD}/projects.html", "w") as f:
    f.write(f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>ExpenseTrack Pro - Project Directory</title>
<style>{CSS}</style></head>
<body>
{nav_html("Project Directory")}
<div class="container">
<h1>Active Project Directory — Q4 2025</h1>
<p style="color:#607d8b;margin-bottom:20px;font-size:14px;">All expense submissions must reference a valid project code from this directory. Charges to inactive or non-existent codes will be flagged for review.</p>
<div class="card" style="padding:0;overflow:hidden;">
<table>
<tr><th>Code</th><th>Project Name</th><th>Department</th><th>Q4 Budget</th><th>Status</th></tr>
""")
    for p in projects:
        f.write(f'<tr><td style="font-weight:600">{p["code"]}</td><td>{p["name"]}</td><td>{p["dept"]}</td><td>${p["budget"]:,}</td><td><span class="tag tag-active">{p["status"]}</span></td></tr>\n')
    f.write("</table></div></div></body></html>")

print("Web application generated successfully.")
PYEOF

# ── 4. Start HTTP server ─────────────────────────────────────────────────
pkill -f "http.server 8080" 2>/dev/null || true
sleep 1
su - ga -c "python3 -m http.server 8080 --directory /tmp/expense_system > /dev/null 2>&1 &"
sleep 2

# Verify server is up
for i in {1..10}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "HTTP server confirmed running on port 8080"
        break
    fi
    sleep 1
done

# ── 5. Write investigation brief to Desktop ──────────────────────────────
cat > /home/ga/Desktop/Q4_Investigation_Brief.txt << 'SPECEOF'
CONFIDENTIAL — INTERNAL AUDIT DIVISION
=======================================
Q4 2025 EXPENSE FRAUD INVESTIGATION BRIEF

TO:      Audit Analyst
FROM:    VP Finance — Internal Controls
DATE:    December 2, 2025
RE:      Anomalies flagged in Q4 expense submissions

The automated anomaly detection system has flagged potential issues in
the Q4 expense data. Your assignment is to investigate three specific
fraud patterns using the ExpenseTrack Pro system at http://localhost:8080.

INVESTIGATION SCOPE:

Pattern 1 — Shell Company Invoices
Two vendor names have been flagged as potential shell companies:
"Pacific Coast Consulting" and "Sterling Associates". Verify whether
these vendors appear in the Approved Vendor Directory. Identify all
transactions submitted to these vendors.

Pattern 2 — Double-Claim Detection
Identify cases where two different employees submitted expenses with
the same vendor, same date, AND same dollar amount. This pattern
indicates the same business event was reimbursed to multiple people.

Pattern 3 — Budget Code Misuse
Review the project codes assigned to transactions (visible in
transaction details — click any row in the ledger). Cross-reference
each project code against the Project Directory. Flag any transaction
charged to a project code that does not exist in the directory, or
where the project description clearly does not match the expense type.

DELIVERABLES:
1. Create ~/Documents/Fraud_Investigation/report.txt with findings
   organized into three sections (one per pattern). For each flagged
   transaction, include: employee name, transaction ID, date, vendor
   name, dollar amount, and which fraud pattern it matches.

2. Bookmark the Expense Ledger page and the Project Directory page
   in a Chrome bookmark folder named "Active Investigation".

3. Set Chrome's download directory to ~/Documents/Fraud_Investigation.
SPECEOF
chown ga:ga /home/ga/Desktop/Q4_Investigation_Brief.txt

# ── 6. Kill existing Chrome ──────────────────────────────────────────────
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# ── 7. Inject initial bookmarks (some generic work bookmarks) ────────────
python3 << 'PYEOF'
import json, time, uuid, os

chrome_base = str((int(time.time()) + 11644473600) * 1000000)

initial_bookmarks = [
    ("Gmail", "https://mail.google.com"),
    ("Google Calendar", "https://calendar.google.com"),
    ("Company Wiki", "https://wiki.example.com"),
    ("Jira", "https://jira.example.com"),
    ("Slack", "https://app.slack.com"),
]

children = []
for i, (name, url) in enumerate(initial_bookmarks):
    children.append({
        "date_added": chrome_base,
        "date_last_used": "0",
        "guid": str(uuid.uuid4()),
        "id": str(i + 1),
        "name": name,
        "type": "url",
        "url": url
    })

bm = {
    "checksum": "",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": chrome_base,
            "date_last_used": "0",
            "date_modified": chrome_base,
            "guid": str(uuid.uuid4()),
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {
            "children": [],
            "date_added": chrome_base,
            "date_last_used": "0",
            "date_modified": "0",
            "guid": str(uuid.uuid4()),
            "id": "2",
            "name": "Other bookmarks",
            "type": "folder"
        },
        "synced": {
            "children": [],
            "date_added": chrome_base,
            "date_last_used": "0",
            "date_modified": "0",
            "guid": str(uuid.uuid4()),
            "id": "3",
            "name": "Mobile bookmarks",
            "type": "folder"
        }
    },
    "version": 1
}

for d in ["/home/ga/.config/google-chrome/Default",
          "/home/ga/.config/google-chrome-cdp/Default"]:
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "Bookmarks")
    with open(path, "w") as f:
        json.dump(bm, f, indent=2)
    os.chmod(path, 0o666)
PYEOF

# ── 8. Launch Chrome to the dashboard ────────────────────────────────────
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh http://localhost:8080 > /tmp/chrome_launch.log 2>&1 &"

# ── 9. Wait for Chrome window ────────────────────────────────────────────
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome\|Chromium"; then
        break
    fi
    sleep 1
done
sleep 2

# ── 10. Maximize Chrome ──────────────────────────────────────────────────
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# ── 11. Initial screenshot ───────────────────────────────────────────────
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== expense_fraud_investigation setup complete ==="
