#!/bin/bash
set -e

echo "=== Setting up Vendor Evaluation Report Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Clean up any previous task artifacts
rm -f /home/ga/Documents/Avalon_Vendor_Eval_2025.odt 2>/dev/null || true
rm -f /home/ga/Documents/vendor_proposals.json 2>/dev/null || true

# 3. Create the realistic data file
cat > /home/ga/Documents/vendor_proposals.json << 'JSONEOF'
{
  "company_info": {
    "name": "Avalon Precision Manufacturing, Inc.",
    "address": "7820 Industrial Parkway, Mentor, OH 44060",
    "project_code": "AVL-PROC-2025-017",
    "author": "Marcus Kasprzak, Senior Procurement Manager",
    "annual_spend_usd": 620000
  },
  "evaluation_criteria": [
    { "id": "C1", "name": "Product Quality & Performance", "weight_pct": 25 },
    { "id": "C2", "name": "Pricing & Total Cost of Ownership", "weight_pct": 20 },
    { "id": "C3", "name": "Delivery & Lead Times", "weight_pct": 15 },
    { "id": "C4", "name": "Technical Support & Engineering", "weight_pct": 15 },
    { "id": "C5", "name": "Quality Certifications", "weight_pct": 10 },
    { "id": "C6", "name": "Financial Stability", "weight_pct": 10 },
    { "id": "C7", "name": "Sustainability", "weight_pct": 5 }
  ],
  "vendors": [
    {
      "name": "Titanium Edge Tooling",
      "hq": "Latrobe, PA",
      "specialization": "Carbide end mills, aerospace coatings",
      "pricing": {
        "annual_quote": 587400,
        "payment_terms": "Net 45"
      },
      "scores": { "C1": 9, "C2": 7, "C3": 8, "C4": 9, "C5": 10, "C6": 9, "C7": 6 }
    },
    {
      "name": "PrecisionCut International",
      "hq": "Schaumburg, IL",
      "specialization": "Indexable inserts, high-feed milling",
      "pricing": {
        "annual_quote": 542800,
        "payment_terms": "Net 60"
      },
      "scores": { "C1": 8, "C2": 9, "C3": 9, "C4": 7, "C5": 9, "C6": 8, "C7": 8 }
    },
    {
      "name": "Nordic Carbide Solutions",
      "hq": "Charlotte, NC (Imported)",
      "specialization": "Solid carbide drills, Scandinavian steel",
      "pricing": {
        "annual_quote": 611200,
        "payment_terms": "Net 30"
      },
      "scores": { "C1": 10, "C2": 5, "C3": 6, "C4": 8, "C5": 10, "C6": 9, "C7": 9 }
    },
    {
      "name": "Summit Tool & Die Works",
      "hq": "Dayton, OH",
      "specialization": "Custom form tools, regional supplier",
      "pricing": {
        "annual_quote": 498600,
        "payment_terms": "Net 30"
      },
      "scores": { "C1": 7, "C2": 10, "C3": 10, "C4": 6, "C5": 8, "C6": 6, "C7": 5 }
    }
  ],
  "report_structure": {
    "required_sections": [
      "Executive Summary",
      "Evaluation Methodology",
      "Vendor Profiles",
      "Weighted Scoring Matrix",
      "Cost Analysis",
      "Recommendation"
    ]
  }
}
JSONEOF

chown ga:ga /home/ga/Documents/vendor_proposals.json
chmod 644 /home/ga/Documents/vendor_proposals.json

# 4. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 5. Ensure OpenOffice Writer is running (task implies app is open)
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            echo "OpenOffice Writer detected"
            break
        fi
        sleep 1
    done
fi

# 6. Maximize and focus window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="