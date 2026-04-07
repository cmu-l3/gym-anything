#!/bin/bash
echo "=== Setting up cve_patch_prioritization task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

VULN_FILE="/home/ga/Documents/vuln_scan_results.xlsx"
rm -f "$VULN_FILE" 2>/dev/null || true

# Generate realistic scan data
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

random.seed(42)

wb = Workbook()

# Asset Inventory
ws_asset = wb.active
ws_asset.title = "Asset_Inventory"
headers_asset = ["Server_ID", "Hostname", "Environment", "Impact", "Team_Owner"]
ws_asset.append(headers_asset)

teams = ["Web", "Database", "Infrastructure", "HR_IT", "Finance"]
envs = ["Prod", "Dev"]
impacts = ["High", "Medium", "Low"]

for i in range(1, 51):
    ws_asset.append([f"SRV-{i:03d}", f"host-{i}.internal", random.choice(envs), random.choice(impacts), random.choice(teams)])

# NVD_CVE_Info
ws_cve = wb.create_sheet("NVD_CVE_Info")
headers_cve = ["CVE_ID", "Description", "Base_Score", "Severity", "Exploit_Maturity"]
ws_cve.append(headers_cve)

maturities = ["Unproven", "Proof_of_Concept", "Functional", "High"]

for i in range(1, 101):
    score = round(random.uniform(4.0, 10.0), 1)
    sev = "Critical" if score >= 9.0 else "High" if score >= 7.0 else "Medium"
    ws_cve.append([f"CVE-2023-{10000+i}", f"Remote code execution vulnerability {i}", score, sev, random.choice(maturities)])

# Scan_Data
ws_scan = wb.create_sheet("Scan_Data")
headers_scan = ["Scan_ID", "Server_ID", "CVE_ID"]
ws_scan.append(headers_scan)

for i in range(1, 201):
    ws_scan.append([f"SCN-{i:04d}", f"SRV-{random.randint(1,50):03d}", f"CVE-2023-{random.randint(10001,10100)}"])

# Formatting
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9D9D9', end_color='D9D9D9', fill_type='solid')
for ws in [ws_asset, ws_cve, ws_scan]:
    for cell in ws[1]:
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal='center')
    for col in ws.columns:
        ws.column_dimensions[col[0].column_letter].width = 18

wb.save('/home/ga/Documents/vuln_scan_results.xlsx')
PYEOF

chown ga:ga "$VULN_FILE"

# Start WPS Spreadsheet
su - ga -c "DISPLAY=:1 et '$VULN_FILE' > /dev/null 2>&1 &"
sleep 6

DISPLAY=:1 wmctrl -r "vuln_scan_results" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "vuln_scan_results" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="