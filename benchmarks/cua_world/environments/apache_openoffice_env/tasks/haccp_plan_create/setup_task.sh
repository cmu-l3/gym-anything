#!/bin/bash
set -e
echo "=== Setting up HACCP Plan Creation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# 1. Create the data file with realistic food safety content
cat > /home/ga/Documents/facility_haccp_data.json << 'JSONEOF'
{
  "document": {
    "number": "HCG-HACCP-2024-001",
    "title": "HACCP Plan — Central Production Kitchen",
    "version": "2.0",
    "effective_date": "2024-11-01",
    "prepared_by": "Elena Marchetti, Food Safety Director"
  },
  "facility": {
    "company_name": "Harborview Culinary Group, LLC",
    "facility_name": "Central Production Kitchen",
    "address": "2100 Whetstone Way, Suite B, Baltimore, MD 21230",
    "phone": "(443) 555-0187",
    "size_sqft": 6800,
    "operating_hours": "5:00 AM – 11:00 PM, 7 days/week",
    "employees": 38,
    "serves": ["Inner Harbor Bistro", "Federal Hill Grill", "Canton Waterfront Kitchen", "Harbor Events Catering"]
  },
  "haccp_team": [
    {"name": "Elena Marchetti", "title": "Food Safety Director", "role": "Team Leader", "certifications": ["SQF Practitioner", "ServSafe Manager"]},
    {"name": "James Okafor", "title": "Executive Chef", "role": "Process Expert", "certifications": ["ACF CEC", "ServSafe Manager"]},
    {"name": "Diane Kowalski", "title": "Kitchen Ops Manager", "role": "Records Coordinator", "certifications": ["HACCP Certified"]},
    {"name": "Dr. Amit Reddy", "title": "Consultant", "role": "Technical Advisor", "affiliation": "Johns Hopkins Public Health"}
  ],
  "products": [
    {"category": "Proteins", "items": ["Grilled chicken", "Short ribs", "Salmon", "Shrimp"]},
    {"category": "Soups/Sauces", "items": ["Marinara", "Crab soup", "Béchamel"]},
    {"category": "RTE", "items": ["Salads", "Desserts", "Cold sandwiches"]}
  ],
  "hazard_analysis_summary": [
    {"step": "Receiving", "hazard": "Pathogen growth (Salmonella, Listeria) if temp abused", "control": "CCP-1"},
    {"step": "Cooking", "hazard": "Survival of vegetative pathogens", "control": "CCP-2"},
    {"step": "Cooling", "hazard": "Spore germination (C. perfringens)", "control": "CCP-3"},
    {"step": "Hot Holding", "hazard": "Toxin production (S. aureus)", "control": "CCP-4"},
    {"step": "Cold Transport", "hazard": "Pathogen growth during transit", "control": "CCP-5"}
  ],
  "critical_control_points": [
    {
      "id": "CCP-1",
      "step": "Receiving",
      "limit": "Refrigerated ≤41°F; Frozen ≤0°F",
      "monitoring": "Check temp of every TCS delivery with calibrated probe",
      "corrective_action": "Reject shipment if >41°F"
    },
    {
      "id": "CCP-2",
      "step": "Cooking",
      "limit": "Poultry ≥165°F; Ground Meat ≥155°F; Seafood ≥145°F (all for 15s)",
      "monitoring": "Internal temp of each batch at thickest point",
      "corrective_action": "Continue cooking until limit met"
    },
    {
      "id": "CCP-3",
      "step": "Cooling",
      "limit": "135°F→70°F in 2h; 70°F→41°F in 4h (Total 6h)",
      "monitoring": "Check temps at 0h, 2h, and 6h",
      "corrective_action": "Rapid chill (ice bath/blast chiller) or reheat to 165°F"
    },
    {
      "id": "CCP-4",
      "step": "Hot Holding",
      "limit": "Maintain ≥135°F",
      "monitoring": "Check temp every 30 mins",
      "corrective_action": "Reheat to 165°F if <1h; discard if >1h"
    },
    {
      "id": "CCP-5",
      "step": "Cold Holding/Transport",
      "limit": "Maintain ≤41°F",
      "monitoring": "Check temp every 2h and at delivery",
      "corrective_action": "Rapid chill if <2h; discard if >4h"
    }
  ]
}
JSONEOF

chown ga:ga /home/ga/Documents/facility_haccp_data.json

# 2. Clear any existing output
rm -f /home/ga/Documents/Harborview_HACCP_Plan_2024.odt 2>/dev/null || true

# 3. Ensure OpenOffice Writer is running and ready
# Kill any existing instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Launch Writer
echo "Starting OpenOffice Writer..."
su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice"; then
        echo "Writer window found"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "OpenOffice" 2>/dev/null || true

# 4. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="