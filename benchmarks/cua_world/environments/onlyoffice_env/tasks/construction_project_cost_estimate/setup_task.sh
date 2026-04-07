#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Construction Cost Estimate Task ==="

echo $(date +%s) > /tmp/construction_project_cost_estimate_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# ============================
# Create project specifications
# ============================
SPECS_PATH="$DOCS_DIR/project_specifications.txt"

cat > "$SPECS_PATH" << 'EOF'
================================================================================
LAKEWOOD MEDICAL PARTNERS - MEDICAL OFFICE BUILD-OUT
Project No: LMP-2024-0847
Location: 550 Commerce Drive, Suite 200, Lakewood, CO 80226
================================================================================

PROJECT OVERVIEW
----------------
Type: Medical Office Build-Out (Tenant Improvement)
Gross Area: 4,200 SF
Occupancy: Business (Group B) / Ambulatory Care
Building: Existing 2-story commercial shell, concrete frame
Scope: Interior build-out from shell condition

Reference: RSMeans 2024 Square Foot Costs reports a 7,000 SF 1-story
medical office at $236.56/SF (union, with 25% contractor fees + 9%
architectural fees). This project is a tenant improvement (TI) build-out,
which typically costs 40-80% of full ground-up construction.

PROGRAM REQUIREMENTS
---------------------

1. RECEPTION & WAITING AREA (420 SF)
   - Reception desk with transaction counter (12 LF built-in millwork)
   - Waiting area seating for 12 patients
   - Check-in/check-out window
   - Flooring: Luxury vinyl tile (LVT)
   - Ceiling: 2x4 acoustic lay-in tile, 9'-0" AFF

2. EXAM ROOMS (6 rooms x 120 SF each = 720 SF)
   - Each room: exam table, sink with cabinet, wall-mounted equipment
   - Flooring: Sheet vinyl (medical grade)
   - Casework: 8 LF base cabinets + 8 LF wall cabinets per room
   - Medical gas outlets: oxygen and suction per room

3. PROCEDURE ROOM (200 SF)
   - Surgical-grade flooring (seamless epoxy)
   - Enhanced HVAC with HEPA filtration
   - Medical gas: O2, N2O, suction, compressed air
   - Emergency power circuit

4. PHYSICIAN OFFICES (3 offices x 150 SF = 450 SF)
   - Carpet tile flooring
   - Data/voice cabling: 2 drops per office

5. NURSE STATION (180 SF)
   - Built-in workstation millwork (16 LF)
   - Flooring: LVT
   - 4 data drops

6. LABORATORY / SPECIMEN COLLECTION (160 SF)
   - Chemical-resistant countertops (12 LF)
   - Specimen refrigerator power/plumbing
   - Eye wash station
   - Sheet vinyl flooring

7. BREAK ROOM (140 SF)
   - Kitchenette with sink, base/wall cabinets (10 LF)
   - LVT flooring

8. RESTROOMS (3 ADA-compliant x 60 SF = 180 SF)
   - Ceramic tile floor and wainscot (48" AFF)
   - ADA fixtures and accessories
   - Exhaust ventilation

9. STORAGE / SERVER ROOM (120 SF)
   - Dedicated HVAC cooling (1-ton mini-split)
   - Fire-rated walls (1-hour)
   - 3 server racks with dedicated 30A circuits

10. CORRIDORS & CIRCULATION (630 SF)
    - LVT flooring throughout
    - Handrails per ADA
    - Emergency/exit signage and lighting

MECHANICAL (HVAC)
-----------------
- System: Variable air volume (VAV) with dedicated AHU
- Zoning: 8 zones minimum
- Exam rooms: individual thermostatic control
- Procedure room: 100% outside air capability, positive pressure
- Server room: dedicated mini-split (1-ton)
- Total cooling: approximately 14 tons
- Ductwork: galvanized sheet metal, insulated supply

ELECTRICAL
----------
- New 400A, 208/120V, 3-phase service panel
- Emergency power: automatic transfer switch, connection to building generator
- Lighting: LED recessed throughout, surgical LED in procedure room
- Receptacles per NEC for medical occupancy
- Fire alarm: addressable system, integration with building

PLUMBING
--------
- Domestic hot/cold water: 3/4" copper mains
- Medical gas: piped O2, suction, N2O (procedure room)
- Waste: connection to building sanitary, acid-waste for lab
- 6 lavatory sinks (exam rooms), 3 ADA fixtures, 2 utility sinks

FIRE PROTECTION
---------------
- Sprinkler system: wet pipe, quick-response heads
- Fire-rated corridor: 1-hour rated partitions
- Fire/smoke dampers at rated wall penetrations

DATA / TELECOM
--------------
- Structured cabling: Cat6A, 32 drops total
- Wireless access points: 6 locations
- Server rack: patch panels, UPS

FINISHES SCHEDULE
-----------------
- Partitions: Metal stud framing, 5/8" Type X gypsum board (both sides)
  Total partition length: approximately 850 LF (walls)
  Wall area (8'-6" stud height): approximately 14,450 SF of gypsum board
- Painting: 2 coats latex, all walls and ceilings
- Ceiling: 2x4 acoustic tile throughout (except procedure room: GWB with
  cleanable paint finish)
- Doors: 22 solid-core wood doors, hardware per ADA, 3 with card readers

PERMITS & FEES
--------------
- Building permit: ~1.5% of construction cost
- Plan review: ~0.8% of construction cost
- Health department inspection fees: $2,500 flat

GENERAL CONDITIONS
------------------
- Duration: 16 weeks
- General contractor overhead: 10% of direct costs
- General contractor profit: 8% of (direct costs + overhead)
- Contingency: 5% of total construction cost
- Performance bond: 2% of contract value
EOF

chown ga:ga "$SPECS_PATH"

# ============================
# Create material prices CSV
# ============================
MATERIALS_PATH="$WORKSPACE_DIR/material_prices.csv"

cat > "$MATERIALS_PATH" << 'CSVEOF'
Division,CSI_Code,Item,Unit,Unit_Cost,Source,Notes
03 - Concrete,03300,Concrete topping/patching,SF,4.25,RSMeans 2024 Unit Costs,For leveling existing slab
05 - Metals,05500,Metal stud framing - 3-5/8" 20ga,LF,3.85,RSMeans 2024 Unit Costs,Non-load-bearing partitions
05 - Metals,05500,Metal stud framing - top/bottom track,LF,1.95,RSMeans 2024 Unit Costs,Track for partitions
06 - Wood/Millwork,06200,Reception desk millwork (custom),LF,485.00,RSMeans 2024 Unit Costs,Built-in with transaction counter
06 - Wood/Millwork,06200,Exam room base cabinets,LF,210.00,RSMeans 2024 Unit Costs,Medical-grade laminate
06 - Wood/Millwork,06200,Exam room wall cabinets,LF,165.00,RSMeans 2024 Unit Costs,Medical-grade laminate
06 - Wood/Millwork,06200,Nurse station millwork,LF,325.00,RSMeans 2024 Unit Costs,Built-in workstation
06 - Wood/Millwork,06200,Break room cabinets (base+wall),LF,195.00,RSMeans 2024 Unit Costs,Standard grade
06 - Wood/Millwork,06200,Lab countertops (chemical-resistant),LF,285.00,RSMeans 2024 Unit Costs,Epoxy resin surface
07 - Thermal/Moisture,07210,Batt insulation R-13 (partition),SF,1.15,RSMeans 2024 Unit Costs,Sound attenuation
07 - Thermal/Moisture,07840,Firestopping at penetrations,EA,45.00,RSMeans 2024 Unit Costs,UL-listed system
08 - Doors/Windows,08110,Solid-core wood door with frame,EA,685.00,RSMeans 2024 Unit Costs,3'-0" x 7'-0" birch
08 - Doors/Windows,08710,Door hardware set (ADA lever),EA,245.00,RSMeans 2024 Unit Costs,Commercial grade
08 - Doors/Windows,08710,Card reader access control,EA,1850.00,RSMeans 2024 Unit Costs,Proximity reader + controller
09 - Finishes,09250,Gypsum board 5/8" Type X,SF,2.35,RSMeans 2024 Unit Costs,Fire-rated drywall
09 - Finishes,09250,Gypsum board finishing (Level 4),SF,1.85,RSMeans 2024 Unit Costs,Tape/mud/sand
09 - Finishes,09310,Ceramic tile floor,SF,12.50,RSMeans 2024 Unit Costs,Medical-grade porcelain
09 - Finishes,09310,Ceramic tile wainscot,SF,14.75,RSMeans 2024 Unit Costs,48" AFF in restrooms
09 - Finishes,09650,Luxury vinyl tile (LVT),SF,6.85,RSMeans 2024 Unit Costs,Commercial medical grade
09 - Finishes,09650,Sheet vinyl (medical grade),SF,8.45,RSMeans 2024 Unit Costs,Welded seam type
09 - Finishes,09680,Carpet tile,SF,4.95,RSMeans 2024 Unit Costs,Commercial 28oz nylon
09 - Finishes,09720,Seamless epoxy flooring,SF,14.50,RSMeans 2024 Unit Costs,Procedure room grade
09 - Finishes,09900,Painting - latex 2 coats,SF,1.65,RSMeans 2024 Unit Costs,Walls and ceilings
09 - Finishes,09510,Acoustic ceiling tile (2x4),SF,4.85,RSMeans 2024 Unit Costs,Armstrong or equal
09 - Finishes,09510,Ceiling grid system,SF,2.15,RSMeans 2024 Unit Costs,Standard 15/16" grid
10 - Specialties,10155,Toilet partitions (ADA),EA,1250.00,RSMeans 2024 Unit Costs,Solid plastic
10 - Specialties,10800,Toilet accessories set,EA,485.00,RSMeans 2024 Unit Costs,Stainless steel ADA set
10 - Specialties,10155,ADA grab bars (pair),EA,185.00,RSMeans 2024 Unit Costs,18" + 42" stainless
10 - Specialties,10440,Fire extinguisher w/ cabinet,EA,285.00,RSMeans 2024 Unit Costs,ABC type
10 - Specialties,10400,Emergency exit signage,EA,165.00,RSMeans 2024 Unit Costs,LED illuminated
12 - Furnishings,12345,Window blinds (per window),EA,225.00,RSMeans 2024 Unit Costs,1" aluminum mini-blind
15 - Mechanical,15050,Plumbing - lavatory sink w/ faucet,EA,650.00,RSMeans 2024 Unit Costs,ADA-compliant medical
15 - Mechanical,15050,Plumbing - ADA toilet,EA,875.00,RSMeans 2024 Unit Costs,Floor-mounted ADA
15 - Mechanical,15050,Plumbing - utility sink,EA,425.00,RSMeans 2024 Unit Costs,Stainless steel
15 - Mechanical,15050,Plumbing rough-in per fixture,EA,1250.00,RSMeans 2024 Unit Costs,Water/waste/vent
15 - Mechanical,15050,Eye wash station,EA,685.00,RSMeans 2024 Unit Costs,Emergency type
15 - Mechanical,15050,Medical gas outlet (O2/suction),EA,1450.00,RSMeans 2024 Unit Costs,Installed per NFPA 99
15 - Mechanical,15050,Medical gas outlet (N2O),EA,1850.00,RSMeans 2024 Unit Costs,Procedure room only
15 - Mechanical,15050,Compressed air outlet,EA,1250.00,RSMeans 2024 Unit Costs,Medical grade
15 - Mechanical,15600,HVAC - VAV box,EA,2850.00,RSMeans 2024 Unit Costs,Including controls
15 - Mechanical,15600,HVAC - Air handling unit (14-ton),EA,42500.00,RSMeans 2024 Unit Costs,Custom medical AHU
15 - Mechanical,15600,HVAC ductwork (galvanized),LB,8.50,RSMeans 2024 Unit Costs,Installed with insulation
15 - Mechanical,15600,HVAC - Mini-split (1-ton),EA,4500.00,RSMeans 2024 Unit Costs,Server room dedicated
15 - Mechanical,15600,HVAC - HEPA filter unit,EA,3200.00,RSMeans 2024 Unit Costs,Procedure room
15 - Mechanical,15600,Thermostatic zone valve,EA,485.00,RSMeans 2024 Unit Costs,Individual room control
15 - Mechanical,15600,Fire/smoke damper,EA,650.00,RSMeans 2024 Unit Costs,At rated partitions
16 - Electrical,16050,Main electrical panel (400A),EA,8500.00,RSMeans 2024 Unit Costs,208/120V 3-phase
16 - Electrical,16050,Sub-panel (100A),EA,2850.00,RSMeans 2024 Unit Costs,Branch distribution
16 - Electrical,16050,Automatic transfer switch,EA,6500.00,RSMeans 2024 Unit Costs,Emergency power
16 - Electrical,16400,LED recessed light (2x4),EA,185.00,RSMeans 2024 Unit Costs,Standard
16 - Electrical,16400,LED recessed light (surgical),EA,2450.00,RSMeans 2024 Unit Costs,Procedure room
16 - Electrical,16050,Duplex receptacle,EA,165.00,RSMeans 2024 Unit Costs,Installed
16 - Electrical,16050,Dedicated circuit (20A),EA,485.00,RSMeans 2024 Unit Costs,Equipment circuits
16 - Electrical,16050,Dedicated circuit (30A),EA,685.00,RSMeans 2024 Unit Costs,Server rack circuits
16 - Electrical,16700,Fire alarm - addressable panel,EA,4500.00,RSMeans 2024 Unit Costs,Integration with building
16 - Electrical,16700,Fire alarm - pull station,EA,285.00,RSMeans 2024 Unit Costs,Manual pull
16 - Electrical,16700,Fire alarm - smoke detector,EA,165.00,RSMeans 2024 Unit Costs,Addressable
16 - Electrical,16700,Fire alarm - strobe/horn,EA,225.00,RSMeans 2024 Unit Costs,ADA compliant
16 - Electrical,16720,Structured cabling - Cat6A drop,EA,285.00,RSMeans 2024 Unit Costs,Cable/jack/patch
16 - Electrical,16720,Wireless access point,EA,485.00,RSMeans 2024 Unit Costs,Enterprise grade
16 - Electrical,16720,Server rack (42U),EA,1850.00,RSMeans 2024 Unit Costs,With cable management
16 - Electrical,16720,Patch panel (48-port),EA,685.00,RSMeans 2024 Unit Costs,Cat6A loaded
16 - Electrical,16720,UPS (3kVA),EA,2250.00,RSMeans 2024 Unit Costs,Rack-mounted
21 - Fire Protection,21100,Sprinkler head (quick-response),EA,125.00,RSMeans 2024 Unit Costs,Concealed pendant
21 - Fire Protection,21100,Sprinkler piping and fitting,SF,4.85,RSMeans 2024 Unit Costs,Per SF of coverage
CSVEOF

# Add source attribution note to end of materials file
cat >> "$MATERIALS_PATH" << 'NOTEEOF'

# DATA SOURCE NOTES:
# Material unit costs sourced from RSMeans 2024 Square Foot Costs and
# RSMeans 2024 Building Construction Cost Data, published by Gordian Group.
# RSMeans reference model: Medical Office, 1 Story, 7,000 SF
# Published total cost: $236.56/SF (union) / $215.55/SF (open shop)
# Subtotal: $173.62/SF + 25% contractor fees + 9% architectural fees
# Unit costs adjusted for tenant improvement scope (interior build-out only).
# ENR Construction Cost Index (2024) used for regional adjustment baseline.
NOTEEOF

chown ga:ga "$MATERIALS_PATH"

# ============================
# Create labor rates CSV
# ============================
LABOR_PATH="$WORKSPACE_DIR/labor_rates.csv"

cat > "$LABOR_PATH" << 'CSVEOF'
Trade,Base_Rate_Hr,Fringe_Hr,Total_Rate_Hr,Productivity_Factor,Source,Notes
General Laborer,35.80,20.45,56.25,1.0,DOL Davis-Bacon (Los Angeles County CA),Clean-up and material handling
Carpenter (rough),52.27,29.83,82.10,1.0,DOL Davis-Bacon (Los Angeles County CA),Metal stud framing and blocking
Carpenter (finish),52.27,29.83,82.10,0.9,DOL Davis-Bacon (Los Angeles County CA),Millwork and door installation
Drywall Installer,47.15,25.30,72.45,1.0,DOL Davis-Bacon (Los Angeles County CA),Hang and finish gypsum board
Painter,40.25,22.18,62.43,1.0,DOL Davis-Bacon (Los Angeles County CA),Prep and 2-coat application
Tile Setter,43.25,24.60,67.85,0.85,DOL Davis-Bacon (Los Angeles County CA),Floor and wall ceramic tile
Flooring Installer,47.15,25.30,72.45,1.0,DOL Davis-Bacon (Los Angeles County CA),LVT/sheet vinyl/carpet (Drywall/floor rate)
Plumber/Pipefitter,58.62,31.41,90.03,0.9,DOL Davis-Bacon (Los Angeles County CA),Rough and finish plumbing
HVAC Sheet Metal Worker,48.90,32.15,81.05,0.9,DOL Davis-Bacon (Los Angeles County CA),Ductwork and equipment
Electrician,55.35,24.80,80.15,0.9,DOL Davis-Bacon (Los Angeles County CA),Power/lighting/low-voltage
Ironworker (Structural),46.50,38.60,85.10,0.95,DOL Davis-Bacon (Los Angeles County CA),Misc metals and supports
Fire Sprinkler Fitter,58.62,31.41,90.03,0.95,DOL Davis-Bacon (Los Angeles County CA),Pipe and head installation (Pipefitter rate)
Fire Alarm Technician,55.35,24.80,80.15,0.9,DOL Davis-Bacon (Los Angeles County CA),Panel/device/programming (Electrician rate)
Low Voltage Technician,55.35,24.80,80.15,1.0,DOL Davis-Bacon (Los Angeles County CA),Data cabling and termination (Electrician rate)
Insulation Worker,41.50,27.90,69.40,1.0,DOL Davis-Bacon (Los Angeles County CA),Batt and pipe insulation
Ceiling Installer,47.15,25.30,72.45,1.0,DOL Davis-Bacon (Los Angeles County CA),Grid and tile (Drywall rate)
Cement Mason,44.90,26.80,71.70,1.0,DOL Davis-Bacon (Los Angeles County CA),Concrete patching and epoxy prep
Operating Engineer,52.15,30.25,82.40,1.0,DOL Davis-Bacon (Los Angeles County CA),Equipment operation
Glazier,49.80,28.50,78.30,1.0,DOL Davis-Bacon (Los Angeles County CA),Interior glazing and windows
Roofer,42.50,18.75,61.25,1.0,DOL Davis-Bacon (Los Angeles County CA),Waterproofing (if applicable)
CSVEOF

# Add source attribution note to end of labor file
cat >> "$LABOR_PATH" << 'NOTEEOF'

# DATA SOURCE NOTES:
# Labor rates from U.S. Department of Labor Davis-Bacon Act Prevailing Wage
# Determinations for Los Angeles County, California (Building Construction).
# Published at sam.gov under General Decision Number CA20240001.
# Rates include base hourly wage + fringe benefits (health/welfare, pension,
# vacation, training fund contributions).
# Productivity factors account for medical office complexity per RSMeans
# crew productivity standards.
# Reference: RSMeans 2024 Data (Gordian Group) for crew composition and
# productivity benchmarks.
NOTEEOF

chown ga:ga "$LABOR_PATH"

echo "Source files created:"
echo "  - $SPECS_PATH"
echo "  - $MATERIALS_PATH (RSMeans 2024 unit costs)"
echo "  - $LABOR_PATH (DOL Davis-Bacon prevailing wages)"

# Open the material prices CSV in ONLYOFFICE
echo "Launching ONLYOFFICE..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$MATERIALS_PATH' > /tmp/onlyoffice_construction_task.log 2>&1 &"

if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_construction_task.log || true
fi

if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

protect_onlyoffice_from_oom

su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

focus_onlyoffice_window

su - ga -c "DISPLAY=:1 import -window root /tmp/construction_project_cost_estimate_setup_screenshot.png" || true

echo "=== Construction Cost Estimate Task Setup Complete ==="
