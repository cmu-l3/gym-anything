#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Appliance Lifecycle Cost Optimizer Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with messy appliance data
SHEET_PATH="$WORKSPACE_DIR/appliance_decision.xlsx"

cat > /tmp/create_appliance_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()

# ============================================================================
# Sheet 1: Raw Data (messy, realistic data that needs to be organized)
# ============================================================================
ws1 = wb.active
ws1.title = "Raw Data"

# Add messy retailer quotes
ws1['A1'] = 'RETAILER QUOTES - COLLECTED FROM 3 STORES'
ws1['A1'].font = Font(bold=True, size=12)

ws1['A3'] = 'WASHERS:'
ws1['A4'] = 'BestBuy - GE Standard Washer: $599 + $89 delivery = $688 total'
ws1['A5'] = "Lowe's - Whirlpool Standard: $649 (free delivery included)"
ws1['A6'] = "Home Depot - Samsung EcoWash (efficient): $849 + free delivery"

ws1['A8'] = 'DRYERS:'
ws1['A9'] = "Lowe's - Standard Electric Dryer: $549 + $50 delivery = $599"
ws1['A10'] = 'BestBuy - Standard Dryer: $529 + $89 delivery = $618'
ws1['A11'] = 'Home Depot - LG EcoDry (efficient): $729 + free delivery'

ws1['A13'] = 'DISHWASHERS:'
ws1['A14'] = 'Home Depot - Standard Dishwasher: $479 + $120 installation = $599'
ws1['A15'] = 'BestBuy - Bosch Standard: $569 + $89 delivery = $658'
ws1['A16'] = "Lowe's - Bosch Efficient 300 Series: $799 (installation included)"

# Energy ratings section
ws1['A18'] = 'ENERGY RATINGS FROM ENERGYSTAR.GOV & PRODUCT LABELS'
ws1['A18'].font = Font(bold=True, size=11)

ws1['A20'] = 'Washer Energy Usage:'
ws1['A21'] = 'Current old washer (est. from manual): 285 kWh/year, 6,200 gallons water/year'
ws1['A22'] = 'Standard new washer: 198 kWh/year, 4,500 gallons/year'
ws1['A23'] = 'Efficient new washer: 112 kWh/year, 3,200 gallons/year'

ws1['A25'] = 'Dryer Energy Usage:'
ws1['A26'] = 'Current old dryer (est.): 920 kWh/year'
ws1['A27'] = 'Standard new dryer: 769 kWh/year'
ws1['A28'] = 'Efficient new dryer: 504 kWh/year'

ws1['A30'] = 'Dishwasher Energy Usage:'
ws1['A31'] = 'Current old dishwasher (est.): 380 kWh/year, 2,600 gallons/year'
ws1['A32'] = 'Standard new dishwasher: 270 kWh/year, 1,800 gallons/year'
ws1['A33'] = 'Efficient new dishwasher: 230 kWh/year, 1,400 gallons/year'

# Repair quotes
ws1['A35'] = 'REPAIR QUOTES (from local appliance repair shop)'
ws1['A35'].font = Font(bold=True, size=11)

ws1['A37'] = 'Washer repair (motor replacement): $285'
ws1['A38'] = 'Dryer repair (heating element + belt): $340'
ws1['A39'] = 'Dishwasher repair (pump + seal): $225'
ws1['A40'] = 'NOTE: Technician said these are 15-yr old appliances, repairs may only last 2-3 years'

# Utility rates
ws1['A42'] = 'UTILITY RATES (from last bill)'
ws1['A42'].font = Font(bold=True, size=11)

ws1['A44'] = 'Electricity: $0.13 per kWh'
ws1['A45'] = 'Water + Sewer combined: $0.008 per gallon'

# Maintenance cost estimates
ws1['A47'] = 'EXPECTED REPAIR COSTS (annual average over 10 years)'
ws1['A47'].font = Font(bold=True, size=11)

ws1['A49'] = 'Old appliances (15+ years): expect $120/year in repairs per appliance'
ws1['A50'] = 'New standard appliances: expect $80/year in repairs per appliance'
ws1['A51'] = 'New efficient appliances (better warranty): expect $50/year in repairs'

# ============================================================================
# Sheet 2: Comparison Matrix (template with headers only)
# ============================================================================
ws2 = wb.create_sheet('Comparison Matrix')

ws2['A1'] = 'APPLIANCE LIFECYCLE COST COMPARISON'
ws2['A1'].font = Font(bold=True, size=14)

ws2['A3'] = 'Input Parameters'
ws2['A3'].font = Font(bold=True, size=12)
ws2['A4'] = 'Analysis Period (years):'
ws2['A5'] = 'Electricity Rate ($/kWh):'
ws2['A6'] = 'Water Rate ($/gallon):'

ws2['A8'] = 'WASHER ANALYSIS'
ws2['A8'].font = Font(bold=True, size=12)
ws2['A9'] = 'Option'
ws2['B9'] = 'Upfront Cost'
ws2['C9'] = 'Annual Energy ($)'
ws2['D9'] = 'Annual Water ($)'
ws2['E9'] = 'Annual Repairs ($)'
ws2['F9'] = '10-Year Total ($)'

ws2['A11'] = '[Add comparison rows for Repair/Standard/Efficient options]'

ws2['A13'] = 'DRYER ANALYSIS'
ws2['A13'].font = Font(bold=True, size=12)

ws2['A15'] = 'DISHWASHER ANALYSIS'
ws2['A15'].font = Font(bold=True, size=12)

ws2['A17'] = 'SUMMARY & RECOMMENDATIONS'
ws2['A17'].font = Font(bold=True, size=12)
ws2['A18'] = 'Appliance'
ws2['B18'] = 'Recommended Option'
ws2['C18'] = '10-Yr Savings vs. Repair ($)'

# Set column widths for readability
ws1.column_dimensions['A'].width = 80
ws2.column_dimensions['A'].width = 25
ws2.column_dimensions['B'].width = 15
ws2.column_dimensions['C'].width = 18
ws2.column_dimensions['D'].width = 18
ws2.column_dimensions['E'].width = 18
ws2.column_dimensions['F'].width = 18

wb.save(sys.argv[1])
print(f"Appliance decision spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_appliance_sheet.py
python3 /tmp/create_appliance_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_appliance_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_appliance_task.log || true
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

echo "=== Appliance Lifecycle Cost Optimizer Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "Your 15-year-old washer, dryer, and dishwasher are all failing."
echo "You have repair quotes and new appliance quotes, but need to compare"
echo "10-year total cost of ownership (purchase + energy + water + repairs)."
echo ""
echo "📝 TASK:"
echo "1. Review the messy data in 'Raw Data' sheet"
echo "2. Switch to 'Comparison Matrix' sheet"
echo "3. Add input parameters: 10 years, \$0.13/kWh, \$0.008/gallon"
echo "4. For EACH appliance (Washer, Dryer, Dishwasher), create comparison rows:"
echo "   - Repair Current: upfront repair cost + ongoing high energy/water + high repair reserve"
echo "   - Buy Standard: purchase cost + moderate energy/water + moderate repairs"
echo "   - Buy Efficient: higher purchase + low energy/water + low repairs"
echo "5. Use FORMULAS to calculate:"
echo "   - Annual Energy Cost = (kWh/year × rate)"
echo "   - Annual Water Cost = (gallons/year × rate)"
echo "   - 10-Year Total = Upfront + (Annual Energy × 10) + (Annual Water × 10) + (Annual Repairs × 10)"
echo "6. Create Summary section showing recommended option for each appliance"
echo "7. Calculate total savings across all three appliances"
echo "8. Save (Ctrl+S)"
echo ""
echo "💡 EXAMPLE CALCULATIONS:"
echo "Washer - Repair Current:"
echo "  Upfront: \$285"
echo "  Annual Energy: 285 kWh × \$0.13 = \$37.05"
echo "  Annual Water: 6200 gal × \$0.008 = \$49.60"
echo "  Annual Repairs: \$120"
echo "  10-Year Total: \$285 + (\$37.05 × 10) + (\$49.60 × 10) + (\$120 × 10) = \$2,351.50"
echo ""
echo "⚠️  Use the data from 'Raw Data' sheet to fill in your analysis!"