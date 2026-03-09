#!/bin/bash
set -e
echo "=== Setting up Real Estate CMA Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare Directories and Clean State
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
rm -f /home/ga/Documents/CMA_Report_4815_Ridgeview.odt 2>/dev/null || true

# 2. Generate Real Data JSON
cat > /home/ga/Documents/property_data.json << 'EOF'
{
  "report_title": "Comparative Market Analysis",
  "report_date": "2025-01-14",
  "subject_property": {
    "address": "4815 Ridgeview Trail",
    "city": "Austin",
    "state": "TX",
    "zip": "78731",
    "neighborhood": "Northwest Hills",
    "bedrooms": 4,
    "bathrooms": 3,
    "sqft": 2640,
    "lot_acres": 0.28,
    "year_built": 2007,
    "features": [
      "Open floor plan with vaulted ceilings",
      "Chef's kitchen with quartz countertops",
      "Saltwater pool with automatic cover",
      "Mature live oak trees",
      "Hardwood floors"
    ],
    "owner_names": "David and Rebecca Morales"
  },
  "comparable_sales": [
    {
      "address": "3207 Greystone Drive",
      "sale_price": 698000,
      "sale_date": "2024-11-15",
      "sqft": 2580,
      "bedrooms": 4,
      "bathrooms": 3,
      "dom": 29
    },
    {
      "address": "5102 Mesa Drive",
      "sale_price": 715000,
      "sale_date": "2024-10-28",
      "sqft": 2740,
      "bedrooms": 4,
      "bathrooms": 3.5,
      "dom": 22
    },
    {
      "address": "4401 Highland Terrace",
      "sale_price": 672000,
      "sale_date": "2024-12-03",
      "sqft": 2510,
      "bedrooms": 3,
      "bathrooms": 2.5,
      "dom": 47
    },
    {
      "address": "2918 Balcones Drive",
      "sale_price": 725000,
      "sale_date": "2024-09-22",
      "sqft": 2820,
      "bedrooms": 5,
      "bathrooms": 3.5,
      "dom": 18
    },
    {
      "address": "4620 Shoal Creek Boulevard",
      "sale_price": 689000,
      "sale_date": "2024-11-30",
      "sqft": 2600,
      "bedrooms": 4,
      "bathrooms": 3,
      "dom": 34
    },
    {
      "address": "3815 Far West Boulevard",
      "sale_price": 705000,
      "sale_date": "2024-10-10",
      "sqft": 2700,
      "bedrooms": 4,
      "bathrooms": 3,
      "dom": 26
    }
  ],
  "adjustment_factors": {
    "sqft_adjustment": 125,
    "pool_adjustment": 18000,
    "bedroom_adjustment": 15000,
    "bath_adjustment": 8000
  },
  "market_conditions": {
    "area": "Northwest Hills / 78731",
    "median_dom": 38,
    "inventory_months": 2.8,
    "yoy_appreciation": "4.2%",
    "summary": "Seller's market with moderating price growth. High demand for homes with pools and updated kitchens."
  },
  "recommended_price": {
    "range_low": 685000,
    "range_high": 710000,
    "listing_strategy": "List at $699,900 to attract buyers under $700K."
  },
  "agent": {
    "name": "Sarah Chen",
    "brokerage": "Lone Star Realty Group",
    "phone": "(512) 555-0173",
    "email": "sarah.chen@lonestarrealty.example.com"
  }
}
EOF
chown ga:ga /home/ga/Documents/property_data.json
chmod 644 /home/ga/Documents/property_data.json

# 3. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_size.txt

# 4. Launch OpenOffice Writer (Starting State Requirement)
# Kill any existing instances first
pkill -f soffice 2>/dev/null || true
sleep 2

echo "Launching OpenOffice Writer..."
su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "OpenOffice"; then
        echo "Writer window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs (Welcome/Recovery) if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 5. Capture Initial Screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="