#!/bin/bash
echo "=== Setting up corporate_per_diem_reconciliation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Target file
WORKBOOK_PATH="/home/ga/Documents/travel_reconciliation.xlsx"
rm -f "$WORKBOOK_PATH" 2>/dev/null || true

# Generate realistic ledger via python
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Real GSA Data (FY2024 selection)
gsa_rates = {
    "NY_New York City": (306, 79),
    "CA_San Francisco": (334, 79),
    "DC_Washington": (258, 79),
    "IL_Chicago": (230, 79),
    "TX_Austin": (192, 69),
    "FL_Miami": (204, 79),
    "WA_Seattle": (232, 79),
    "MA_Boston": (284, 79),
    "GA_Atlanta": (173, 74),
    "CO_Denver": (199, 79),
    "NV_Las Vegas": (145, 69),
    "AZ_Phoenix": (154, 69),
    "OR_Portland": (176, 74),
    "TN_Nashville": (224, 79),
    "PA_Philadelphia": (214, 79)
}

first_names = ["James", "Mary", "Robert", "Patricia", "John", "Jennifer", "Michael", "Linda", "David", "Elizabeth", "William", "Barbara", "Richard", "Susan", "Joseph", "Jessica", "Thomas", "Sarah", "Charles", "Karen"]
last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin"]

wb = Workbook()

# --- Sheet 1: GSA_Rates ---
ws_gsa = wb.active
ws_gsa.title = "GSA_Rates"
ws_gsa.append(["State_City", "Lodging_Rate", "MIE_Rate"])

for city, (lodging, mie) in gsa_rates.items():
    ws_gsa.append([city, lodging, mie])

# Format headers
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color="4F81BD", end_color="4F81BD", fill_type="solid")
for cell in ws_gsa[1]:
    cell.font = header_font
    cell.fill = header_fill

ws_gsa.column_dimensions['A'].width = 25
ws_gsa.column_dimensions['B'].width = 15
ws_gsa.column_dimensions['C'].width = 15

# --- Sheet 2: Expense_Claims ---
ws_claims = wb.create_sheet("Expense_Claims")
headers = [
    "Claim_ID", "Employee_Name", "State_City", "Travel_Days", 
    "Claimed_Lodging", "Claimed_MIE", 
    "GSA_Lodging_Rate", "GSA_MIE_Rate", 
    "Approved_Lodging", "Approved_MIE", 
    "Total_Reimbursement", "Overage"
]
ws_claims.append(headers)

for cell in ws_claims[1]:
    cell.font = header_font
    cell.fill = header_fill

# Generate ~100 rows
random.seed(42) # Consistent generation
for i in range(1, 101):
    claim_id = f"TRV-{2024000+i}"
    name = f"{random.choice(first_names)} {random.choice(last_names)}"
    city = random.choice(list(gsa_rates.keys()))
    days = random.randint(1, 6)
    
    true_lodging_max = days * gsa_rates[city][0]
    true_mie_max = days * gsa_rates[city][1]
    
    # Mix of compliant and non-compliant claims
    if random.random() > 0.4:
        # Overspent
        claimed_lodging = true_lodging_max + random.randint(10, 250)
        claimed_mie = true_mie_max + random.randint(5, 75)
    else:
        # Under/Exact spent
        claimed_lodging = true_lodging_max - random.randint(0, 100)
        claimed_mie = true_mie_max - random.randint(0, 30)
        
    claimed_lodging = max(50, claimed_lodging) # Ensure no negatives
    claimed_mie = max(20, claimed_mie)
    
    row = [claim_id, name, city, days, claimed_lodging, claimed_mie, "", "", "", "", "", ""]
    ws_claims.append(row)

# Adjust widths
for col_letter in ['A','B','C','D','E','F','G','H','I','J','K','L']:
    ws_claims.column_dimensions[col_letter].width = 18

wb.save("/home/ga/Documents/travel_reconciliation.xlsx")
PYEOF

chown ga:ga "$WORKBOOK_PATH"

# Launch WPS Spreadsheet in the background to ensure initial setup is clean
if ! pgrep -f "et" > /dev/null; then
    su - ga -c "DISPLAY=:1 et '$WORKBOOK_PATH' &"
    
    # Wait for the window to appear
    for i in {1..15}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "travel_reconciliation"; then
            break
        fi
        sleep 1
    done
fi

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="