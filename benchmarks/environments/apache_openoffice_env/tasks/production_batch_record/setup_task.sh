#!/bin/bash
set -e
echo "=== Setting up Production Batch Record Task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up any previous task artifacts
rm -f /home/ga/Documents/BPR-2024-1847.odt 2>/dev/null || true

# Create the batch data JSON file with realistic manufacturing data
cat > /home/ga/Documents/batch_data.json << 'EOF'
{
  "company": {
    "name": "Lakeshore Contract Manufacturing, Inc.",
    "address": "2100 Lakehurst Drive, Waukegan, IL 60085",
    "phone": "(847) 555-0193",
    "fda_registration": "3009876542"
  },
  "product": {
    "name": "Hydrating Facial Serum",
    "sku": "HFS-030-A",
    "fill_volume": "30 mL",
    "formula_version": "3.1"
  },
  "batch": {
    "batch_number": "BPR-2024-1847",
    "batch_size_kg": 150.0,
    "theoretical_yield_units": 4800,
    "manufacturing_date": "2024-11-18",
    "expiry_date": "2026-11-17"
  },
  "raw_materials": [
    {"item": 1, "name": "Purified Water USP", "code": "RM-001", "lot": "WP-2024-0891", "quantity_kg": 112.50},
    {"item": 2, "name": "Hyaluronic Acid", "code": "RM-047", "lot": "HA-24-3361", "quantity_kg": 1.50},
    {"item": 3, "name": "Glycerin USP", "code": "RM-012", "lot": "GL-2024-5540", "quantity_kg": 15.00},
    {"item": 4, "name": "Niacinamide", "code": "RM-089", "lot": "NB3-24-0772", "quantity_kg": 7.50},
    {"item": 5, "name": "Panthenol", "code": "RM-091", "lot": "PB5-24-1183", "quantity_kg": 3.00},
    {"item": 6, "name": "Carbomer 940", "code": "RM-033", "lot": "CB-24-4450", "quantity_kg": 0.75},
    {"item": 7, "name": "Triethanolamine", "code": "RM-034", "lot": "TEA-24-2208", "quantity_kg": 0.45},
    {"item": 8, "name": "Phenoxyethanol", "code": "RM-056", "lot": "PE-24-6601", "quantity_kg": 1.50},
    {"item": 9, "name": "Tocopheryl Acetate", "code": "RM-078", "lot": "VE-24-0339", "quantity_kg": 0.75},
    {"item": 10, "name": "Allantoin", "code": "RM-062", "lot": "AL-24-1177", "quantity_kg": 0.30},
    {"item": 11, "name": "Citric Acid", "code": "RM-021", "lot": "CA-24-8834", "quantity_kg": 0.15},
    {"item": 12, "name": "Fragrance", "code": "RM-FRG-118", "lot": "FR-24-2055", "quantity_kg": 0.60}
  ],
  "equipment": [
    {"id": "EQ-301", "name": "Lee Industries 200L Jacketed Mixing Vessel", "calibration_due": "2025-03-15"},
    {"id": "EQ-302", "name": "Silverson L5M-A High-Shear Mixer", "calibration_due": "2025-01-20"},
    {"id": "EQ-117", "name": "Mettler Toledo ICS469 Platform Scale", "calibration_due": "2025-02-28"},
    {"id": "EQ-222", "name": "Mettler Toledo pH Meter", "calibration_due": "2025-03-01"},
    {"id": "EQ-405", "name": "Filamatic DAB-8 Liquid Filler", "calibration_due": "2025-05-01"}
  ],
  "manufacturing_steps": [
    {"step": 1, "phase": "Water Phase", "instruction": "Charge 112.50 kg Purified Water. Heat to 70C.", "check": "Temp 70+/-2C"},
    {"step": 2, "phase": "Dispersion", "instruction": "Sift Carbomer 940 into water. Mix 30 min.", "check": "No lumps"},
    {"step": 3, "phase": "Active Addition", "instruction": "Cool to 45C. Add Hyaluronic Acid, Glycerin, Niacinamide, Panthenol, Allantoin.", "check": "Dissolved"},
    {"step": 4, "phase": "Neutralization", "instruction": "Add TEA. Mix 10 min.", "check": "pH 5.5-6.5"},
    {"step": 5, "phase": "Oil Phase", "instruction": "Premix Vitamin E, Phenoxyethanol, Fragrance. Add to batch.", "check": "Emulsified"},
    {"step": 6, "phase": "Adjustment", "instruction": "Adjust pH with Citric Acid if needed.", "check": "Final pH 5.5-6.0"},
    {"step": 7, "phase": "Hold", "instruction": "Cool to 25C. Sample for QC.", "check": " QC Release"},
    {"step": 8, "phase": "Filling", "instruction": "Fill 30mL bottles.", "check": "Weight 31.2g"}
  ],
  "in_process_checks": [
    {"id": "IPC-01", "parameter": "Water Temperature", "spec": "70 +/- 2 C"},
    {"id": "IPC-02", "parameter": "Carbomer Dispersion", "spec": "No visible lumps"},
    {"id": "IPC-03", "parameter": "pH after Neutralization", "spec": "5.5 - 6.5"},
    {"id": "IPC-04", "parameter": "Final Bulk pH", "spec": "5.5 - 6.0"},
    {"id": "IPC-05", "parameter": "Viscosity", "spec": "8,000 - 15,000 cP"},
    {"id": "IPC-06", "parameter": "Appearance", "spec": "Clear to slightly opalescent gel"},
    {"id": "IPC-07", "parameter": "Specific Gravity", "spec": "1.02 - 1.06 g/mL"},
    {"id": "IPC-08", "parameter": "Fill Weight", "spec": "31.2 +/- 0.5 g"}
  ],
  "regulatory_references": [
    "21 CFR Part 211",
    "ISO 22716:2007",
    "USP <61>"
  ]
}
EOF
chown ga:ga /home/ga/Documents/batch_data.json
chmod 644 /home/ga/Documents/batch_data.json

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure OpenOffice is running with a blank document
echo "Launching OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    sleep 8
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice"; then
        echo "Writer window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "OpenOffice" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice" 2>/dev/null || true

# Dismiss potential first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="