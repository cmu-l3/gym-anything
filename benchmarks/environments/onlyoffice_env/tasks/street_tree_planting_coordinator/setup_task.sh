#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Street Tree Planting Coordinator Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the tree planting workbook
SHEET_PATH="$WORKSPACE_DIR/StreetTreePlanting.xlsx"

cat > /tmp/create_tree_planting.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
import sys

wb = Workbook()

# Remove default sheet
if 'Sheet' in wb.sheetnames:
    wb.remove(wb['Sheet'])

# ============================================================================
# Sheet 1: Tree Species Reference Data
# ============================================================================
ws_species = wb.create_sheet("TreeSpecies", 0)
ws_species.append([
    "Species Name", "Mature Height (ft)", "Spread", "Root System", 
    "Drought Tolerance", "Pollen Level", "Available Count"
])

species_data = [
    ["Red Maple", 20, "Medium", "Aggressive", "Moderate", "Low", 3],
    ["Japanese Maple", 15, "Small", "Non-aggressive", "Low", "Low", 2],
    ["Dogwood", 18, "Small", "Non-aggressive", "Moderate", "Low", 2],
    ["River Birch", 35, "Large", "Moderate", "High", "Moderate", 4],
    ["Redbud", 22, "Medium", "Non-aggressive", "Moderate", "Low", 3],
    ["Serviceberry", 16, "Small", "Non-aggressive", "Moderate", "Low", 3],
    ["Pin Oak", 45, "Large", "Aggressive", "High", "High", 5],
    ["Linden", 40, "Large", "Moderate", "Moderate", "High", 4]
]

for row in species_data:
    ws_species.append(row)

# Format header
header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF")
for cell in ws_species[1]:
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)

# Set column widths
ws_species.column_dimensions['A'].width = 18
ws_species.column_dimensions['B'].width = 15
ws_species.column_dimensions['C'].width = 12
ws_species.column_dimensions['D'].width = 16
ws_species.column_dimensions['E'].width = 16
ws_species.column_dimensions['F'].width = 12
ws_species.column_dimensions['G'].width = 15

# ============================================================================
# Sheet 2: Planting Sites with Constraints
# ============================================================================
ws_sites = wb.create_sheet("Sites", 1)
ws_sites.append([
    "Site ID", "Address", "Overhead Wires", "Sidewalk Width (ft)", 
    "Resident Preference Notes"
])

sites_data = [
    ["SITE-01", "123 Maple St", "Yes", 4.5, "Wants shade tree, no messy fruit"],
    ["SITE-02", "456 Oak Ave", "No", 6.0, "Prefers flowering tree"],
    ["SITE-03", "789 Elm Blvd", "Yes", 3.5, "Pollen allergy - needs low pollen"],
    ["SITE-04", "234 Pine Rd", "No", 5.5, "Wants fast-growing shade"],
    ["SITE-05", "567 Birch Ln", "Yes", 4.0, "No preference"],
    ["SITE-06", "890 Cedar Dr", "No", 7.0, "Wants native species, good fall color"],
    ["SITE-07", "345 Spruce Way", "Yes", 3.0, "Small space, pollen allergy"],
    ["SITE-08", "678 Willow Ct", "No", 5.0, "Prefers low maintenance"],
    ["SITE-09", "901 Ash Pl", "No", 6.5, "Wants shade, has irrigation system"],
    ["SITE-10", "123 Cherry St", "Yes", 4.5, "Flowering tree preferred"],
    ["SITE-11", "456 Poplar Ave", "No", 8.0, "Large space available, wants big tree"],
    ["SITE-12", "789 Sycamore Rd", "No", 5.5, "No strong preference"]
]

for row in sites_data:
    ws_sites.append(row)

# Format header
for cell in ws_sites[1]:
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)

# Set column widths
ws_sites.column_dimensions['A'].width = 10
ws_sites.column_dimensions['B'].width = 18
ws_sites.column_dimensions['C'].width = 14
ws_sites.column_dimensions['D'].width = 16
ws_sites.column_dimensions['E'].width = 35

# ============================================================================
# Sheet 3: Volunteer Care Captains
# ============================================================================
ws_volunteers = wb.create_sheet("Volunteers", 2)
ws_volunteers.append([
    "Volunteer Name", "Email", "Phone", "Availability"
])

volunteers_data = [
    ["Sarah Chen", "sarah.c@email.com", "555-0101", "Weekday evenings & weekends"],
    ["Mike Johnson", "mikej@email.com", "555-0102", "Weekends only"],
    ["Lisa Patel", "lisa.p@email.com", "555-0103", "Flexible/Work from home"],
    ["Tom Garcia", "tgarcia@email.com", "555-0104", "Weekday mornings"],
    ["Emma Wilson", "emma.w@email.com", "555-0105", "Weekends only"],
    ["David Kim", "david.k@email.com", "555-0106", "Weekday evenings"],
    ["Rachel Brown", "rachel.b@email.com", "555-0107", "Flexible/Retired"]
]

for row in volunteers_data:
    ws_volunteers.append(row)

# Format header
for cell in ws_volunteers[1]:
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal='center', vertical='center')

# Set column widths
ws_volunteers.column_dimensions['A'].width = 18
ws_volunteers.column_dimensions['B'].width = 22
ws_volunteers.column_dimensions['C'].width = 14
ws_volunteers.column_dimensions['D'].width = 30

# ============================================================================
# Sheet 4: Master Plan (Empty Template)
# ============================================================================
ws_plan = wb.create_sheet("Master Plan", 3)
ws_plan.append([
    "Site ID", "Address", "Assigned Species", "Care Captain Name", 
    "Care Captain Phone", "First Year Watering (gallons)", "Rationale"
])

# Pre-fill Site ID and Address from Sites sheet
for i, site_data in enumerate(sites_data, start=2):
    ws_plan.cell(row=i, column=1, value=site_data[0])  # Site ID
    ws_plan.cell(row=i, column=2, value=site_data[1])  # Address
    # Columns 3-7 left blank for user to fill

# Format header
plan_header_fill = PatternFill(start_color="70AD47", end_color="70AD47", fill_type="solid")
for cell in ws_plan[1]:
    cell.fill = plan_header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)

# Set column widths
ws_plan.column_dimensions['A'].width = 10
ws_plan.column_dimensions['B'].width = 18
ws_plan.column_dimensions['C'].width = 18
ws_plan.column_dimensions['D'].width = 18
ws_plan.column_dimensions['E'].width = 16
ws_plan.column_dimensions['F'].width = 20
ws_plan.column_dimensions['G'].width = 40

# Add instruction text below the table
ws_plan.cell(row=15, column=1, value="INSTRUCTIONS:")
ws_plan.cell(row=15, column=1).font = Font(bold=True, size=12)

instructions = [
    "1. Assign a tree species to each site from the TreeSpecies sheet",
    "2. Respect constraints: Sites with overhead wires need trees <25ft tall",
    "3. Narrow sidewalks (<5ft) need non-aggressive root systems",
    "4. Honor pollen allergy requests with low-pollen species",
    "5. Don't exceed available inventory for any species",
    "6. Assign one care captain per site (max 3 sites per volunteer)",
    "7. Calculate first-year watering: ~1,200-1,500 gallons per tree",
    "8. Document your rationale for each species choice"
]

for i, instruction in enumerate(instructions, start=16):
    ws_plan.cell(row=i, column=1, value=instruction)
    ws_plan.merge_cells(f'A{i}:G{i}')
    ws_plan.cell(row=i, column=1).alignment = Alignment(wrap_text=True)

# Add summary section
ws_plan.cell(row=25, column=1, value="SUMMARY CHECKS:")
ws_plan.cell(row=25, column=1).font = Font(bold=True, size=12)

ws_plan.cell(row=26, column=1, value="Total trees assigned:")
ws_plan.cell(row=27, column=1, value="Species diversity (unique species used):")
ws_plan.cell(row=28, column=1, value="Overhead wire constraint violations:")
ws_plan.cell(row=29, column=1, value="Pollen allergy constraint violations:")

# Save workbook
wb.save(sys.argv[1])
print(f"Street Tree Planting workbook created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_tree_planting.py
python3 /tmp/create_tree_planting.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Workbook created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_tree_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_tree_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Street Tree Planting Coordinator Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  • Review TreeSpecies, Sites, and Volunteers sheets"
echo "  • Complete the Master Plan sheet by:"
echo "    - Assigning appropriate tree species to each site"
echo "    - Respecting overhead wire, sidewalk, and pollen constraints"
echo "    - Assigning care captain volunteers"
echo "    - Calculating watering needs"
echo "    - Documenting your rationale"
echo "  • Save when complete (Ctrl+S)"
echo ""
echo "⚠️  Key Constraints:"
echo "  • Overhead wires → trees must be <25ft tall"
echo "  • Narrow sidewalks (<5ft) → non-aggressive roots required"
echo "  • Pollen allergies → low-pollen species required"
echo "  • Limited inventory per species"