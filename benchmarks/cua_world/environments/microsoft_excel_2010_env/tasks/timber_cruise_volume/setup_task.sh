#!/bin/bash
set -e
echo "=== Setting up Timber Cruise Volume Task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Install dependencies for data generation (if needed)
# We assume python3 is available. We need openpyxl or pandas.
# If not available, we use a pre-prepared script or install.
if ! python3 -c "import openpyxl" 2>/dev/null; then
    echo "Installing openpyxl..."
    pip install openpyxl >/dev/null 2>&1 || true
fi

# 3. Generate the Excel file
echo "Generating timber_cruise.xlsx..."
python3 -c '
import openpyxl
from openpyxl.utils import get_column_letter
from openpyxl.styles import Font, PatternFill, Border, Side

wb = openpyxl.Workbook()

# --- SHEET 1: Tree_Data ---
ws_data = wb.active
ws_data.title = "Tree_Data"
headers = ["Tree_ID", "Plot_ID", "Species", "DBH_inches", "Total_Height_ft", "Merch_Height_ft", "Defect_Pct"]
ws_data.append(headers)

# Raw data (80 trees) - subset for brevity in script, but task calls for 80.
# Generating synthetic but realistic data structure based on the prompt description.
import random
random.seed(42)

species_list = ["DF"]*46 + ["WH"]*15 + ["WRC"]*10 + ["RA"]*9
random.shuffle(species_list)

data_rows = []
for i in range(1, 81):
    tree_id = f"T{i:03d}"
    plot_id = (i - 1) // 8 + 1
    sp = species_list[i-1]
    
    # Generate realistic dimensions based on species
    if sp == "DF":
        dbh = round(random.uniform(12, 38), 1)
        ht = int(dbh * 4.5 + random.uniform(-10, 10))
        merch = int(ht * 0.7)
        defect = random.choice([0, 2, 3, 4, 5])
    elif sp == "WH":
        dbh = round(random.uniform(10, 28), 1)
        ht = int(dbh * 4.2 + random.uniform(-10, 10))
        merch = int(ht * 0.65)
        defect = random.choice([5, 6, 7, 8])
    elif sp == "WRC":
        dbh = round(random.uniform(14, 45), 1)
        ht = int(dbh * 3.5 + random.uniform(-15, 15))
        merch = int(ht * 0.6)
        defect = random.choice([8, 10, 12, 15, 18])
    else: # RA
        dbh = round(random.uniform(8, 18), 1)
        ht = int(dbh * 5.0 + random.uniform(-10, 10))
        merch = int(ht * 0.5)
        defect = random.choice([4, 5, 6])
        
    row = [tree_id, plot_id, sp, dbh, ht, merch, defect]
    ws_data.append(row)
    data_rows.append(row)

# Styling
for cell in ws_data[1]:
    cell.font = Font(bold=True)

# --- SHEET 2: Coefficients ---
ws_coef = wb.create_sheet("Coefficients")
ws_coef.append(["Species", "b0", "b1", "Price_Per_MBF", "", "Parameter", "Value"])
ws_coef.append(["DF", -20.43, 0.01838, 650, "", "BAF", 20])
ws_coef.append(["WH", -18.25, 0.01724, 450, "", "Num_Plots", 10])
ws_coef.append(["WRC", -24.87, 0.01682, 900, "", "Stand_Acres", 40])
ws_coef.append(["RA", -12.15, 0.01543, 380])

# Styling
for cell in ws_coef[1]:
    cell.font = Font(bold=True)

# --- SHEET 3: Volume_Calculations ---
ws_calc = wb.create_sheet("Volume_Calculations")
calc_headers = headers + ["Basal_Area_sqft", "TPA", "Gross_BF_Volume", "Net_BF_Volume", "Vol_Per_Acre_BF", "Stumpage_Per_Acre", "Size_Class"]
ws_calc.append(calc_headers)

# Copy data
for row in data_rows:
    ws_calc.append(row)

# Style headers
for cell in ws_calc[1]:
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="CCCCCC", end_color="CCCCCC", fill_type="solid")

# Highlight input columns vs calc columns
for col in range(8, 15):
    cell = ws_calc.cell(row=1, column=col)
    cell.fill = PatternFill(start_color="FFFF00", end_color="FFFF00", fill_type="solid")

# --- SHEET 4: Stand_Summary ---
ws_sum = wb.create_sheet("Stand_Summary")
ws_sum.column_dimensions["A"].width = 5
ws_sum.column_dimensions["B"].width = 30
ws_sum.column_dimensions["C"].width = 15

# Section A
ws_sum["B2"] = "A. Per-Acre Volume by Species"
ws_sum["B2"].font = Font(bold=True)
ws_sum["B3"] = "Douglas-fir MBF/Acre"
ws_sum["B4"] = "Western hemlock MBF/Acre"
ws_sum["B5"] = "Western red cedar MBF/Acre"
ws_sum["B6"] = "Red alder MBF/Acre"
ws_sum["B7"] = "Total MBF/Acre"
ws_sum["B7"].font = Font(bold=True)

# Section B
ws_sum["B9"] = "B. Stumpage Value by Species"
ws_sum["B9"].font = Font(bold=True)
ws_sum["B10"] = "Douglas-fir $/Acre"
ws_sum["B11"] = "Western hemlock $/Acre"
ws_sum["B12"] = "Western red cedar $/Acre"
ws_sum["B13"] = "Red alder $/Acre"
ws_sum["B14"] = "Total $/Acre"
ws_sum["B14"].font = Font(bold=True)

# Section C
ws_sum["B16"] = "C. Stand Totals (40 Acres)"
ws_sum["B16"].font = Font(bold=True)
ws_sum["B17"] = "Total Stand Volume (MBF)"
ws_sum["B18"] = "Total Stand Value ($)"
ws_sum["B19"] = "Avg Trees Per Acre"

# Section D
ws_sum["B21"] = "D. Stand Metrics"
ws_sum["B21"].font = Font(bold=True)
ws_sum["B22"] = "Quadratic Mean Diameter (in)"
ws_sum["B23"] = "Basal Area Per Acre (sq ft)"
ws_sum["B24"] = "Harvest Eligibility"

# Save
output_path = "C:\\Users\\Docker\\Documents\\timber_cruise.xlsx"
wb.save(output_path)
print(f"Created {output_path}")
'

# 4. Prepare Environment
# Ensure Excel is running with the file
if ! pgrep -f "EXCEL.EXE" > /dev/null; then
    echo "Starting Excel..."
    # Using the standard environment path or command
    # Note: In the env definition, hooks use powershell. We are in bash here (WSL/Cygwin context or cross-platform).
    # Since this is a Windows env managed via Docker/Wine or VM, we use the 'su - ga' pattern if Linux-based Wine,
    # or powershell/cmd invocation if native Windows. 
    # Based on the env spec (microsoft_excel_2010_env), it uses "powershell" in hooks.
    # However, the task interface uses setup_task.sh (bash). 
    # The framework likely executes bash on the host or a compatibility layer.
    # We will assume a Windows environment where we can call powershell.exe.
    
    FILE_PATH="C:\\Users\\Docker\\Documents\\timber_cruise.xlsx"
    
    # Launch Excel via PowerShell to ensure it detaches correctly
    powershell.exe -Command "Start-Process 'C:\\Program Files\\Microsoft Office\\Office14\\EXCEL.EXE' -ArgumentList '$FILE_PATH' -WindowStyle Maximized"
    
    sleep 10
else
    echo "Excel already running, opening file..."
    FILE_PATH="C:\\Users\\Docker\\Documents\\timber_cruise.xlsx"
    powershell.exe -Command "Start-Process '$FILE_PATH'"
    sleep 5
fi

# 5. UI Setup (Maximize)
# Using nircmd or powershell to maximize if wmctrl is not available (common in Windows)
# But sticking to standard task patterns provided:
powershell.exe -Command "
\$w = Get-Process | Where-Object {\$_.MainWindowTitle -like '*Excel*'}
if (\$w) { 
    [void] [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
    [Microsoft.VisualBasic.Interaction]::AppActivate(\$w.Id) 
    # SendKeys to Maximize (Alt+Space, X) is flaky, but we assume Start-Process -WindowStyle Maximized worked.
}
" || true

# 6. Initial Screenshot
# Use a windows screenshot tool or the provided 'scrot' if running in a hybrid env.
# Assuming standard gym_anything screenshot mechanism handles the screen capture at step end.
echo "Setup complete."