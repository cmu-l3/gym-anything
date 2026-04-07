#!/bin/bash
set -e

echo "=== Setting up Repair MLS Data Pipeline Task ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/mls_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/api"
sudo -u ga mkdir -p "$WORKSPACE_DIR/transformers"
sudo -u ga mkdir -p "$WORKSPACE_DIR/analytics"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"

# ─────────────────────────────────────────────────────────────
# Create sample data
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/data/sample_reso.json" << 'EOF'
{
  "@odata.context": "https://api.mls.com/reso/odata/$metadata#Property",
  "value": [
    {
      "ListingKey": "1001",
      "PropertyType": "Single Family",
      "ListPrice": 450000,
      "LivingArea": 2000,
      "ModificationTimestamp": "2024-03-01T14:30:00Z",
      "Coordinates": "POINT (-122.3321 47.6062)"
    },
    {
      "ListingKey": "1002",
      "PropertyType": "Condo / Townhouse",
      "ListPrice": 320000,
      "LivingArea": 0,
      "ModificationTimestamp": "2024-03-02T09:15:00Z",
      "Coordinates": "POINT (-122.1234 47.5432)"
    }
  ],
  "@odata.nextLink": "https://api.mls.com/reso/odata/Property?$skip=2"
}
EOF

# ─────────────────────────────────────────────────────────────
# api/client.py (BUG: Hardcoded skip instead of nextLink)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/api/client.py" << 'EOF'
import requests

def fetch_all_listings(base_url):
    """Fetch all listings from the RESO Web API."""
    listings = []
    skip = 0
    
    # BUG: Hardcoded pagination loop ignores @odata.nextLink
    while skip < 300: 
        url = f"{base_url}?$top=100&$skip={skip}"
        response = requests.get(url).json()
        
        listings.extend(response.get('value', []))
        
        # We should be checking response.get('@odata.nextLink')
        if not response.get('value'):
            break
            
        skip += 100
        
    return listings
EOF

# ─────────────────────────────────────────────────────────────
# transformers/datetime_utils.py (BUG: Naive vs Aware datetime)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/transformers/datetime_utils.py" << 'EOF'
from datetime import datetime, timezone

def is_active_listing(modification_timestamp_str):
    """Check if a listing was modified within the last 30 days."""
    
    # BUG: strptime creates a naive datetime, which crashes when compared to UTC aware now()
    dt = datetime.strptime(modification_timestamp_str, "%Y-%m-%dT%H:%M:%SZ")
    
    now = datetime.now(timezone.utc)
    
    delta = now - dt
    return delta.days < 30
EOF

# ─────────────────────────────────────────────────────────────
# transformers/property_mapper.py (BUG: Missing Enum)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/transformers/property_mapper.py" << 'EOF'
def map_property_type(raw_type):
    """Map MLS property types to internal standard schema."""
    mapping = {
        "Single Family": "SFR",
        "Condominium": "CONDO",  # API changed this to "Condo / Townhouse"
        "Multi-Family": "MULTI",
        "Commercial": "COM",
        "Land": "LOT"
    }
    
    # BUG: Will raise KeyError for new "Condo / Townhouse" value
    return mapping[raw_type]
EOF

# ─────────────────────────────────────────────────────────────
# transformers/spatial.py (BUG: Regex misses negative coordinates)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/transformers/spatial.py" << 'EOF'
import re

def parse_wkt_point(wkt_string):
    """Parse Well-Known Text POINT to lat/lon dict."""
    if not wkt_string:
        return None
        
    # BUG: \d+\.\d+ misses the negative sign (-) on longitudes
    match = re.search(r'POINT\s*\(\s*(\d+\.\d+)\s+(\d+\.\d+)\s*\)', wkt_string)
    
    if match:
        return {
            "lon": float(match.group(1)),
            "lat": float(match.group(2))
        }
    return None
EOF

# ─────────────────────────────────────────────────────────────
# analytics/price_stats.py (BUG: Zero division)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/analytics/price_stats.py" << 'EOF'
import statistics

def calculate_median_ppsqft(listings):
    """Calculate the median price per square foot across listings."""
    if not listings:
        return 0.0
        
    # BUG: Does not filter out sqft=0 or missing data, causing ZeroDivisionError
    ppsqft_values = []
    for p in listings:
        price = p.get('ListPrice', 0)
        sqft = p.get('LivingArea', 0)
        
        ppsqft = price / sqft
        ppsqft_values.append(ppsqft)
        
    return statistics.median(ppsqft_values) if ppsqft_values else 0.0
EOF

# ─────────────────────────────────────────────────────────────
# tests/test_pipeline.py (Visible test suite)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_pipeline.py" << 'EOF'
import pytest
from datetime import datetime, timezone, timedelta
from transformers.datetime_utils import is_active_listing
from transformers.property_mapper import map_property_type
from transformers.spatial import parse_wkt_point
from analytics.price_stats import calculate_median_ppsqft

def test_timezone_check():
    recent = (datetime.now(timezone.utc) - timedelta(days=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
    assert is_active_listing(recent) == True

def test_property_mapper():
    assert map_property_type("Single Family") == "SFR"
    assert map_property_type("Condo / Townhouse") == "CONDO"

def test_spatial_parser():
    res = parse_wkt_point("POINT (-122.3321 47.6062)")
    assert res is not None
    assert res['lon'] < 0

def test_price_stats():
    data = [
        {"ListPrice": 300000, "LivingArea": 1000},
        {"ListPrice": 400000, "LivingArea": 0} # Should be ignored
    ]
    assert calculate_median_ppsqft(data) == 300.0
EOF

# Set ownership
chown -R ga:ga "$WORKSPACE_DIR"

# Launch VS Code
echo "Launching VS Code..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="