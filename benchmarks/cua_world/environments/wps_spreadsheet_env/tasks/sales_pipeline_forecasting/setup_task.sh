#!/bin/bash
echo "=== Setting up sales_pipeline_forecasting task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

INPUT_FILE="/home/ga/Documents/pipeline_forecast.xlsx"
rm -f "$INPUT_FILE" 2>/dev/null || true
rm -f "/home/ga/Documents/pipeline_forecast_completed.xlsx" 2>/dev/null || true

# Generate realistic CRM data using python
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

random.seed(42)

wb = Workbook()
ws_opps = wb.active
ws_opps.title = 'Opportunities'

# Generate Opportunities
headers = ['Opportunity_ID', 'Account_Name', 'Owner', 'Close_Date', 'Stage', 'Amount']
ws_opps.append(headers)

reps = ['Darcel C. Miller', 'Vicki M. Lee', 'John A. Smith', 'Sarah B. Jones']
stages = ['Discovery', 'Qualified', 'Proposal', 'Negotiation', 'Closed Won']
companies = ['Acme Corp', 'Globex', 'Soylent', 'Initech', 'Umbrella Corp', 'Stark Ind', 'Wayne Ent', 'Massive Dynamic']

for i in range(1, 201):
    opp_id = f"OPP-{1000+i}"
    account = f"{random.choice(companies)} {random.randint(1, 100)}"
    owner = random.choice(reps)
    month = random.randint(10, 12)
    day = random.randint(1, 28)
    close_date = f"2023-{month:02d}-{day:02d}"
    stage = random.choice(stages)
    # Generate realistic B2B SaaS amounts
    amount = round(random.uniform(10000, 150000), 2)
    ws_opps.append([opp_id, account, owner, close_date, stage, amount])

# Format Opps headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9E1F2', end_color='D9E1F2', fill_type='solid')
for cell in ws_opps[1]:
    cell.font = header_font
    cell.fill = header_fill

# Generate Stage Probabilities Sheet
ws_probs = wb.create_sheet('Stage_Probabilities')
ws_probs.append(['Stage', 'Probability'])
ws_probs.append(['Discovery', 0.10])
ws_probs.append(['Qualified', 0.25])
ws_probs.append(['Proposal', 0.50])
ws_probs.append(['Negotiation', 0.75])
ws_probs.append(['Closed Won', 1.00])

for cell in ws_probs[1]:
    cell.font = header_font
    cell.fill = header_fill

# Format probabilities as percentage
for row in ws_probs.iter_rows(min_row=2, max_row=6, min_col=2, max_col=2):
    for cell in row:
        cell.number_format = '0%'

# Adjust column widths
ws_opps.column_dimensions['A'].width = 15
ws_opps.column_dimensions['B'].width = 25
ws_opps.column_dimensions['C'].width = 20
ws_opps.column_dimensions['E'].width = 15
ws_opps.column_dimensions['F'].width = 12
ws_probs.column_dimensions['A'].width = 20
ws_probs.column_dimensions['B'].width = 15

wb.save('/home/ga/Documents/pipeline_forecast.xlsx')
print(f"Created pipeline forecast with 200 opportunities.")
PYEOF

chown ga:ga "$INPUT_FILE" 2>/dev/null || true

# Kill any existing instances for clean start
pkill -f "et" 2>/dev/null || true
sleep 1

# Launch WPS Spreadsheet targeting the input file
su - ga -c "DISPLAY=:1 et '$INPUT_FILE' &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "WPS Spreadsheets"; then
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true
sleep 2

# Dismiss any potential dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="