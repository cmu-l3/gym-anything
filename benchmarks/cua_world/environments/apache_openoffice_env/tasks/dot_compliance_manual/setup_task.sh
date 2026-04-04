#!/bin/bash
# Setup script for dot_compliance_manual task
# Generates the fleet_data.json file and prepares the environment

echo "=== Setting up DOT Compliance Manual Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up any previous task artifacts
rm -f /home/ga/Documents/GLFL_DOT_Compliance_Manual.odt 2>/dev/null || true
rm -f /home/ga/Documents/fleet_data.json 2>/dev/null || true

# Generate the fleet_data.json file with realistic data
echo "Generating fleet data..."
cat > /home/ga/Documents/fleet_data.json << 'JSONEOF'
{
  "company_info": {
    "legal_name": "Great Lakes Freight Lines, Inc.",
    "dba": "GLFL",
    "usdot_number": "1847293",
    "mc_number": "MC-682041",
    "headquarters": {
      "street": "3100 Stickney Avenue",
      "city": "Toledo",
      "state": "OH",
      "zip": "43608"
    },
    "terminals": [
      {"name": "Toledo HQ Terminal", "address": "3100 Stickney Ave, Toledo, OH 43608", "type": "HQ/Terminal", "sqft": 48000},
      {"name": "Detroit Metro Terminal", "address": "27600 Northline Rd, Romulus, MI 48174", "type": "Cross-dock", "sqft": 32000},
      {"name": "Fort Wayne Service Center", "address": "4815 Ardmore Ave, Fort Wayne, IN 46809", "type": "Service Center", "sqft": 24000}
    ],
    "operating_authority_states": ["OH", "MI", "IN", "IL", "WI", "PA"],
    "employees_total": 198,
    "annual_revenue_millions": 37.2,
    "years_in_operation": 28,
    "founded_year": 1996,
    "carrier_type": "Regional LTL (Less-Than-Truckload)",
    "effective_date": "2025-03-01",
    "document_number": "GLFL-DOT-COM-2025-001"
  },
  "key_personnel": [
    {"name": "Sandra Kowalski", "title": "Fleet Compliance Officer", "phone": "419-555-0147", "email": "s.kowalski@glflines.com", "responsibility": "DOT regulatory compliance, audit preparation, CSA monitoring"},
    {"name": "Michael Brennan", "title": "VP of Operations / Designated Safety Director", "phone": "419-555-0102", "email": "m.brennan@glflines.com", "responsibility": "Overall safety program oversight, FMCSA liaison, accident review board chair"},
    {"name": "James Okafor", "title": "Maintenance Manager", "phone": "419-555-0138", "email": "j.okafor@glflines.com", "responsibility": "Preventive maintenance program, DVIR review, annual inspections"},
    {"name": "Dr. Patricia Reeves", "title": "Medical Review Officer (MRO)", "phone": "419-555-0291", "email": "p.reeves@cjocchealth.com", "responsibility": "Drug/alcohol test result verification, SAP referrals"},
    {"name": "Lisa Tran", "title": "Human Resources Director", "phone": "419-555-0115", "email": "l.tran@glflines.com", "responsibility": "Driver qualification files, hiring/termination, training records"},
    {"name": "Robert Dominguez", "title": "Dispatch Operations Manager", "phone": "419-555-0123", "email": "r.dominguez@glflines.com", "responsibility": "Load planning, HOS compliance monitoring, ELD administration"},
    {"name": "Karen Whitfield", "title": "Claims and Insurance Manager", "phone": "419-555-0156", "email": "k.whitfield@glflines.com", "responsibility": "Accident reporting, insurance claims, cargo claims"}
  ],
  "fleet_inventory": {
    "power_units": [
      {"type": "Day Cab Tractor", "count": 52, "primary_make": "Freightliner Cascadia", "model_year_range": "2019-2024"},
      {"type": "Sleeper Cab Tractor", "count": 23, "primary_make": "Kenworth T680", "model_year_range": "2020-2024"},
      {"type": "Straight Truck (26ft)", "count": 12, "primary_make": "International MV607", "model_year_range": "2021-2023"}
    ],
    "trailers": [
      {"type": "53ft Dry Van", "count": 134, "primary_make": "Wabash National DuraPlate", "model_year_range": "2017-2024"},
      {"type": "48ft Flatbed", "count": 28, "primary_make": "Fontaine Infinity", "model_year_range": "2018-2023"}
    ],
    "total_power_units": 87,
    "total_trailers": 162
  },
  "driver_statistics": {
    "total_drivers": 142,
    "cdl_class_a": 98,
    "cdl_class_b": 44,
    "hazmat_endorsed": 23,
    "tanker_endorsed": 8,
    "doubles_triples_endorsed": 31,
    "average_tenure_years": 4.7,
    "average_age": 44,
    "annual_turnover_rate_pct": 38
  },
  "testing_program": {
    "consortium_name": "Great Lakes Transportation Safety Consortium (GLTSC)",
    "consortium_manager": "CJ Occupational Health",
    "consortium_address": "1920 Indian Wood Circle, Suite 200, Maumee, OH 43537",
    "mro_name": "Dr. Patricia Reeves",
    "random_testing_rate_drug_pct": 50,
    "random_testing_rate_alcohol_pct": 10,
    "collection_site": "CJ Occupational Health - Maumee",
    "laboratory": "Quest Diagnostics, Lenexa, KS",
    "sap_provider": "Behavioral Health Associates of NW Ohio"
  },
  "insurance": {
    "carrier": "Zurich North America Commercial",
    "policy_number": "TRK-GL-2024-08817",
    "auto_liability_limit": "$5,000,000 CSL",
    "cargo_liability_limit": "$250,000 per shipment",
    "general_liability_limit": "$2,000,000 aggregate",
    "workers_comp_carrier": "Ohio BWC State Fund",
    "broker": "Marsh McLennan Transportation Practice"
  },
  "regulatory_references": [
    {"part": "49 CFR Part 382", "title": "Controlled Substances and Alcohol Use and Testing"},
    {"part": "49 CFR Part 383", "title": "Commercial Driver's License Standards"},
    {"part": "49 CFR Part 390", "title": "Federal Motor Carrier Safety Regulations - General"},
    {"part": "49 CFR Part 391", "title": "Qualifications of Drivers and Longer Combination Vehicle (LCV) Driver Instructors"},
    {"part": "49 CFR Part 392", "title": "Driving of Commercial Motor Vehicles"},
    {"part": "49 CFR Part 395", "title": "Hours of Service of Drivers"},
    {"part": "49 CFR Part 396", "title": "Inspection, Repair, and Maintenance"},
    {"part": "49 CFR Part 397", "title": "Transportation of Hazardous Materials; Driving and Parking Rules"}
  ],
  "required_sections": [
    {
      "title": "Company Overview and Operating Authority",
      "description": "Company identification, USDOT/MC numbers, operating authority, service area, organizational structure",
      "subsections": ["Company Identification", "Operating Authority and Service Area", "Organizational Chart for Safety Functions"]
    },
    {
      "title": "Driver Qualification Standards",
      "description": "Per 49 CFR Part 391: driver qualification file requirements, application procedures, road test, medical certification",
      "subsections": ["Application for Employment (391.21)", "Driving Record Inquiries (391.23)", "Road Test Requirements (391.31)", "Medical Examiner's Certificate (391.41-391.49)", "Driver Qualification File Contents (391.51)"]
    },
    {
      "title": "Hours of Service Policy",
      "description": "Per 49 CFR Part 395: HOS rules, ELD mandate compliance, supporting documents, exceptions",
      "subsections": ["Property-Carrying Driver HOS Limits (395.3)", "Electronic Logging Device Policy (395.8)", "Supporting Documents and Records of Duty Status (395.11)", "HOS Exceptions and Exemptions"]
    },
    {
      "title": "Vehicle Maintenance and Inspection Program",
      "description": "Per 49 CFR Part 396: systematic maintenance program, DVIRs, periodic inspections, out-of-service criteria",
      "subsections": ["Systematic Preventive Maintenance Program (396.3)", "Driver Vehicle Inspection Reports (396.11-396.13)", "Annual Periodic Inspections (396.17)", "Brake Inspector Qualifications (396.25)", "Out-of-Service Criteria and Roadside Inspections"]
    },
    {
      "title": "Controlled Substances and Alcohol Testing Program",
      "description": "Per 49 CFR Part 382: testing categories, procedures, consequences, SAP referral process",
      "subsections": ["Pre-Employment Testing (382.301)", "Random Testing Program (382.305)", "Post-Accident Testing (382.303)", "Reasonable Suspicion Testing (382.307)", "Return-to-Duty and Follow-Up Testing (382.309-311)", "Consequences of Positive Test or Refusal", "FMCSA Drug and Alcohol Clearinghouse"]
    },
    {
      "title": "Accident Register and Reporting Procedures",
      "description": "Per 49 CFR Part 390: DOT recordable accident definition, register maintenance, post-accident procedures",
      "subsections": ["DOT Recordable Accident Criteria (390.15)", "Accident Register Requirements", "Post-Accident Investigation Procedures", "Post-Accident Drug and Alcohol Testing Triggers"]
    },
    {
      "title": "Hazardous Materials Transportation",
      "description": "Per 49 CFR Part 397: HM driver requirements, routing, parking, and emergency procedures",
      "subsections": ["Hazmat Endorsement Requirements", "Shipping Papers and Placarding Verification", "Routing and Parking Restrictions (397.7-397.11)", "Hazmat Emergency Response Procedures"]
    },
    {
      "title": "Emergency Procedures and Contact Directory",
      "description": "Emergency response contacts, breakdown procedures, severe weather policy, accident scene procedures",
      "subsections": ["Accident Scene Procedures", "Vehicle Breakdown and Roadside Emergency", "Severe Weather and Natural Disaster Policy", "Emergency Contact Directory"]
    }
  ],
  "maintenance_program": {
    "pm_schedule": [
      {"tier": "PM-A (Safety Inspection)", "interval_miles": 15000, "interval_days": 45, "scope": "Brakes, tires, lights, steering, coupling devices, frame"},
      {"tier": "PM-B (Comprehensive)", "interval_miles": 45000, "interval_days": 135, "scope": "PM-A items plus engine, transmission, differential, suspension, electrical"},
      {"tier": "PM-C (Annual)", "interval_miles": 90000, "interval_days": 365, "scope": "PM-B items plus DOT annual inspection, emissions, full chassis inspection"}
    ],
    "repair_authorization_thresholds": {
      "driver_authorization": "$0 - $250",
      "maintenance_manager_authorization": "$251 - $5,000",
      "vp_operations_authorization": "Over $5,000"
    },
    "dvir_policy": "All drivers must complete DVIR at end of each driving day per 49 CFR 396.11. Maintenance department must review and sign off within 24 hours."
  }
}
JSONEOF

# Fix permissions
chown ga:ga /home/ga/Documents/fleet_data.json
chmod 644 /home/ga/Documents/fleet_data.json

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists.txt

# Ensure OpenOffice Writer shortcut is on Desktop
SOFFICE_BIN="/opt/openoffice4/program/soffice"
if [ -x "$SOFFICE_BIN" ]; then
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

# Ensure OpenOffice is running (maximize chance of agent success with window mgmt)
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    echo "Pre-launching OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            break
        fi
        sleep 1
    done
    
    # Maximize window
    DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== DOT Compliance Manual Setup Complete ==="
echo "Data file: /home/ga/Documents/fleet_data.json"
echo "Target: /home/ga/Documents/GLFL_DOT_Compliance_Manual.odt"