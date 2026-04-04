#!/bin/bash
echo "=== Setting up Environmental Impact Summary Task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ensure directories
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up previous runs
rm -f /home/ga/Documents/Ridgeline_Wind_EIA_Summary.odt 2>/dev/null || true
rm -f /home/ga/Documents/project_environmental_data.json 2>/dev/null || true

# Create the data file
cat > /home/ga/Documents/project_environmental_data.json << 'JSONEOF'
{
  "document_info": {
    "document_number": "BREC-EIA-2024-RWE-017",
    "title": "Environmental Impact Assessment — Executive Summary",
    "project_name": "Ridgeline Wind Energy Project",
    "prepared_by": "Blue Ridge Environmental Consulting, Inc.",
    "lead_author": "Dr. Elena Marchetti, Senior Environmental Scientist",
    "date": "November 2024",
    "client": "Appalachian Renewables LLC"
  },
  "project_description": {
    "location": "Backbone Mountain ridgeline, Garrett County, Maryland",
    "total_capacity_mw": 48,
    "num_turbines": 12,
    "turbine_model": "Vestas V136-4.0 MW",
    "hub_height_m": 112,
    "project_area_acres": 2840,
    "permanent_disturbance_acres": 47.3
  },
  "regulatory_framework": [
    "National Environmental Policy Act (NEPA)",
    "Endangered Species Act (ESA) Section 7",
    "Maryland COMAR 26.02 — Air Quality",
    "USFWS Land-Based Wind Energy Guidelines (2012)"
  ],
  "ecological_surveys": {
    "wildlife_species": [
      {
        "common_name": "Indiana Bat",
        "scientific_name": "Myotis sodalis",
        "status": "Federally Endangered",
        "finding": "14 confirmed call sequences; likely migration corridor"
      },
      {
        "common_name": "Allegheny Woodrat",
        "scientific_name": "Neotoma magister",
        "status": "State Endangered",
        "finding": "3 individuals captured in rocky outcrops >400m from turbines"
      },
      {
        "common_name": "Cerulean Warbler",
        "scientific_name": "Setophaga cerulea",
        "status": "Species of Concern",
        "finding": "7 territorial males in mature oak canopy"
      },
      {
        "common_name": "Timber Rattlesnake",
        "scientific_name": "Crotalus horridus",
        "status": "State Endangered",
        "finding": "Denning habitat identified near Turbine T-09"
      }
    ]
  },
  "noise_impact_assessment": {
    "methodology": "ISO 9613-2",
    "limit_dba": 55,
    "receptors": [
      {"id": "R-01", "loc": "Henline Residence", "dist_m": 680, "dba": 42.1, "compliant": true},
      {"id": "R-02", "loc": "Frazee Farm", "dist_m": 520, "dba": 46.8, "compliant": true},
      {"id": "R-03", "loc": "Mt. Zion Church", "dist_m": 1100, "dba": 37.4, "compliant": true},
      {"id": "R-04", "loc": "Bittinger Store", "dist_m": 1450, "dba": 34.2, "compliant": true}
    ]
  },
  "visual_impact": {
    "summary": "Turbines visible from 38% of area within 16 km ZTV. Moderate impact from Appalachian Trail spur."
  },
  "mitigation_measures": [
    {
      "category": "Bat Mortality",
      "measure": "Operational curtailment (cut-in speed 6.0 m/s) July-Oct",
      "responsible": "Operations Manager"
    },
    {
      "category": "Rattlesnake Protection",
      "measure": "Seasonal construction restriction (Oct 1 - Apr 30) near den",
      "responsible": "General Contractor"
    },
    {
      "category": "Visual",
      "measure": "Radar-activated lighting system (ADLS)",
      "responsible": "Appalachian Renewables"
    }
  ],
  "required_sections": [
    "Project Description",
    "Regulatory Framework",
    "Ecological Resources",
    "Noise Impact",
    "Visual Impact",
    "Water Resources",
    "Mitigation Plan",
    "Conclusions"
  ]
}
JSONEOF
chown ga:ga /home/ga/Documents/project_environmental_data.json
chmod 644 /home/ga/Documents/project_environmental_data.json

# Record start time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists.txt

# Create desktop shortcut for Writer if needed
if [ ! -f /home/ga/Desktop/openoffice-writer.desktop ] && [ -x /opt/openoffice4/program/soffice ]; then
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=/opt/openoffice4/program/soffice
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="