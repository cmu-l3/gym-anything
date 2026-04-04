#!/bin/bash
set -e

echo "=== Setting up Excavation Report Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory and clean up
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/UNM-OCA-2024-031.odt
rm -f /home/ga/Documents/site_data.json

# 2. Write the JSON data file
cat > /home/ga/Documents/site_data.json << 'EOF'
{
  "site_info": {
    "site_number": "LA 189274",
    "site_name": "Coyote Springs Pueblo",
    "county": "Sandoval",
    "state": "New Mexico",
    "landowner": "Bureau of Land Management",
    "cultural_affiliation": "Ancestral Pueblo (AD 1050-1300)"
  },
  "project_info": {
    "report_title": "Preliminary Excavation Report: Coyote Springs Pueblo",
    "principal_investigator": "Dr. Elena Vasquez, Ph.D., RPA",
    "report_number": "UNM-OCA-2024-031",
    "submitted_to": "New Mexico State Historic Preservation Office (SHPO)"
  },
  "excavation_units": [
    {
      "unit_id": "EU-1",
      "location": "Room Block A, Room 3",
      "strata": [
        {"stratum": "I", "description": "Aeolian sand, light brown (10YR 6/3)"},
        {"stratum": "II", "description": "Cultural fill, dark brown (7.5YR 4/2)"},
        {"stratum": "III", "description": "Structured fill/collapsed adobe"},
        {"stratum": "IV", "description": "Floor surface, compacted clay"}
      ]
    },
    {
      "unit_id": "EU-2",
      "location": "Room Block A, Room 5",
      "strata": [
        {"stratum": "I", "description": "Aeolian sand"},
        {"stratum": "II", "description": "Roof fall and cultural fill"},
        {"stratum": "III", "description": "Floor surface, hard-packed clay"}
      ]
    },
    {
      "unit_id": "EU-3",
      "location": "Midden area",
      "strata": [
        {"stratum": "I", "description": "Recent overburden"},
        {"stratum": "II", "description": "Upper midden deposit"},
        {"stratum": "III", "description": "Lower midden"}
      ]
    },
    {
      "unit_id": "EU-4",
      "location": "Plaza area",
      "strata": [
        {"stratum": "I", "description": "Surface sand"},
        {"stratum": "II", "description": "Plaza surface, compacted"},
        {"stratum": "III", "description": "Sub-plaza fill"}
      ]
    }
  ],
  "features": [
    {"feature_id": "F-1", "type": "Hearth", "location": "EU-1", "description": "Basin-shaped hearth with fire-reddened clay lining"},
    {"feature_id": "F-2", "type": "Adobe wall", "location": "EU-1/EU-2", "description": "North wall of Room 3, puddled adobe"},
    {"feature_id": "F-3", "type": "Storage cist", "location": "EU-2", "description": "Sub-floor storage cist with intact bowl"},
    {"feature_id": "F-4", "type": "Post hole", "location": "EU-2", "description": "Roof support post hole"},
    {"feature_id": "F-5", "type": "Extramural hearth", "location": "EU-4", "description": "Shallow basin hearth in plaza"}
  ],
  "artifact_inventory": [
    {"category": "Ceramics - Decorated", "count": 347, "types": "Gallup B/w, Red Mesa B/w, Puerco B/w"},
    {"category": "Ceramics - Utility", "count": 892, "types": "Indented corrugated, Plain gray"},
    {"category": "Lithics - Chipped", "count": 523, "types": "Debitage, Projectile points, Bifaces"},
    {"category": "Lithics - Ground", "count": 31, "types": "Manos, Metates"},
    {"category": "Faunal Bone", "count": 284, "types": "Rabbit, Deer, Turkey"}
  ],
  "dating_results": [
    {"sample_id": "C14-001", "method": "AMS Radiocarbon", "result": "880 +/- 30 BP", "calibrated": "AD 1049-1222"},
    {"sample_id": "C14-002", "method": "AMS Radiocarbon", "result": "810 +/- 25 BP", "calibrated": "AD 1176-1271"},
    {"sample_id": "DENDRO-001", "method": "Dendrochronology", "result": "Cutting date: AD 1198", "calibrated": "Absolute"}
  ],
  "preliminary_interpretations": "Occupation during Pueblo II-III transition, ca. AD 1050-1250. Multi-room habitation with storage and plaza. Mixed farming-foraging economy.",
  "required_sections": [
    "Introduction and Project Background",
    "Environmental Setting",
    "Cultural Context",
    "Field Methods",
    "Excavation Results by Unit",
    "Feature Descriptions",
    "Artifact Analysis",
    "Chronometric Dating Results",
    "Preliminary Interpretations",
    "Recommendations",
    "References Cited"
  ]
}
EOF

# Set ownership
chown ga:ga /home/ga/Documents/site_data.json
chmod 644 /home/ga/Documents/site_data.json

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch OpenOffice Writer
if ! pgrep -f "soffice" > /dev/null; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            echo "Writer window found"
            break
        fi
        sleep 1
    done
fi

# 5. Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# 6. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="