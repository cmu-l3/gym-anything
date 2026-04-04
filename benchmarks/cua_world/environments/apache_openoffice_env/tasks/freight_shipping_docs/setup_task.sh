#!/bin/bash
# Setup script for freight_shipping_docs task

echo "=== Setting up Freight Shipping Docs Task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/GLI_BOL_2024_03847.odt 2>/dev/null || true
rm -f /home/ga/Documents/shipment_data.json 2>/dev/null || true

# 3. Create the input JSON data file
cat > /home/ga/Documents/shipment_data.json << 'JSONEOF'
{
  "document": {
    "bol_number": "GLI-BOL-2024-03847",
    "document_title": "Master Bill of Lading — Multi-Stop LTL Shipment",
    "shipment_date": "2024-11-18",
    "pro_number": "GLI-847291034"
  },
  "carrier": {
    "name": "Great Lakes Intermodal Transport, Inc.",
    "address": "8400 West 47th Street, McCook, IL 60525",
    "mc_number": "MC-487291",
    "usdot_number": "2847193",
    "scac_code": "GLIT",
    "phone": "(708) 555-0142",
    "dispatcher": "Raul Espinoza",
    "driver_name": "Dennis Kowalski",
    "tractor_number": "T-2247",
    "trailer_number": "GLI-53F-0891"
  },
  "shipper": {
    "name": "Consolidated Industrial Supply Co.",
    "address": "2200 Busse Road, Elk Grove Village, IL 60007",
    "contact": "Patricia Hwang, Shipping Manager",
    "phone": "(847) 555-0238",
    "pickup_date": "2024-11-18",
    "pickup_window": "06:00-09:00 CST",
    "dock_assignment": "Dock 7B",
    "special_instructions": "Forklift required. Hazmat placards must be displayed before departure. Driver must present photo ID and carrier authority letter."
  },
  "delivery_stops": [
    {
      "stop_number": 1,
      "facility_name": "Precision Machining Associates",
      "address": "1475 Industrial Parkway",
      "city": "Akron",
      "state": "OH",
      "zip": "44310",
      "contact": "James Mercer, Receiving Supervisor",
      "phone": "(330) 555-0187",
      "delivery_window": "2024-11-19 08:00-12:00 EST",
      "items_delivering": ["LI-001", "LI-002", "LI-010", "LI-011"],
      "special_instructions": "Dock height 48 inches. Call 30 minutes before arrival."
    },
    {
      "stop_number": 2,
      "facility_name": "Great River Manufacturing",
      "address": "5600 River Road",
      "city": "Davenport",
      "state": "IA",
      "zip": "52802",
      "contact": "Sandra Olsen, Plant Manager",
      "phone": "(563) 555-0294",
      "delivery_window": "2024-11-20 07:00-11:00 CST",
      "items_delivering": ["LI-003", "LI-004", "LI-005", "LI-008"],
      "special_instructions": "HAZMAT delivery - facility has spill containment area at Dock 3. Driver must have current HAZMAT endorsement on CDL."
    },
    {
      "stop_number": 3,
      "facility_name": "Northern Tier Fabricators",
      "address": "3200 Highway 10 West",
      "city": "Moorhead",
      "state": "MN",
      "zip": "56560",
      "contact": "Erik Lindqvist, Operations Director",
      "phone": "(218) 555-0163",
      "delivery_window": "2024-11-21 09:00-14:00 CST",
      "items_delivering": ["LI-006", "LI-007", "LI-009", "LI-012"],
      "special_instructions": "Final stop. Return trailer GLI-53F-0891 to McCook terminal after delivery. Appointment required - confirm with Erik 24 hours prior."
    }
  ],
  "line_items": [
    {"line_id": "LI-001", "description": "Cold-Drawn Steel Tubing, 2-inch OD, 20-ft lengths", "nmfc_code": "170700", "freight_class": 65, "pieces": 6, "package_type": "Bundle", "weight_lbs": 3240, "dimensions_inches": "240 x 24 x 24", "hazmat": false, "delivery_stop": 1},
    {"line_id": "LI-002", "description": "Double-Acting Hydraulic Cylinders, 3000 PSI rated", "nmfc_code": "100240", "freight_class": 85, "pieces": 4, "package_type": "Crate", "weight_lbs": 1860, "dimensions_inches": "48 x 36 x 30", "hazmat": false, "delivery_stop": 1},
    {"line_id": "LI-003", "description": "Industrial Adhesive, Solvent-Based Contact Cement", "nmfc_code": "004620", "freight_class": 55, "pieces": 2, "package_type": "Drum", "weight_lbs": 440, "dimensions_inches": "24 x 24 x 36", "hazmat": true, "hazmat_details": {"un_number": "UN1133", "proper_shipping_name": "Adhesives, containing flammable liquid", "hazard_class": "3", "hazard_class_description": "Flammable Liquid", "packing_group": "II", "erg_guide": "127", "placard_required": "FLAMMABLE 3"}, "delivery_stop": 2},
    {"line_id": "LI-004", "description": "Vitrified Abrasive Grinding Wheels, 14-inch diameter", "nmfc_code": "016400", "freight_class": 70, "pieces": 8, "package_type": "Carton", "weight_lbs": 920, "dimensions_inches": "18 x 18 x 16", "hazmat": false, "delivery_stop": 2},
    {"line_id": "LI-005", "description": "Three-Phase Electric Motors, 15 HP, TEFC Enclosure", "nmfc_code": "140700", "freight_class": 85, "pieces": 3, "package_type": "Pallet", "weight_lbs": 1350, "dimensions_inches": "48 x 40 x 32", "hazmat": false, "delivery_stop": 2},
    {"line_id": "LI-006", "description": "Compressed Nitrogen Gas Cylinders, Size 300", "nmfc_code": "065100", "freight_class": 65, "pieces": 4, "package_type": "Cylinder", "weight_lbs": 680, "dimensions_inches": "10 x 10 x 60", "hazmat": true, "hazmat_details": {"un_number": "UN1066", "proper_shipping_name": "Nitrogen, compressed", "hazard_class": "2.2", "hazard_class_description": "Non-Flammable Gas", "packing_group": "N/A", "erg_guide": "121", "placard_required": "NON-FLAMMABLE GAS 2"}, "delivery_stop": 3},
    {"line_id": "LI-007", "description": "Bare Copper Wire Spools, 8 AWG, 1000-ft", "nmfc_code": "051680", "freight_class": 65, "pieces": 3, "package_type": "Reel", "weight_lbs": 2310, "dimensions_inches": "36 x 36 x 24", "hazmat": false, "delivery_stop": 3},
    {"line_id": "LI-008", "description": "Schedule 40 PVC Pipe Fittings, assorted elbows and tees", "nmfc_code": "156220", "freight_class": 55, "pieces": 2, "package_type": "Pallet", "weight_lbs": 780, "dimensions_inches": "48 x 40 x 28", "hazmat": false, "delivery_stop": 2},
    {"line_id": "LI-009", "description": "Lithium-Ion Battery Packs, 48V 100Ah, for industrial equipment", "nmfc_code": "018570", "freight_class": 92.5, "pieces": 6, "package_type": "Carton", "weight_lbs": 1440, "dimensions_inches": "24 x 18 x 12", "hazmat": true, "hazmat_details": {"un_number": "UN3481", "proper_shipping_name": "Lithium ion batteries packed with equipment", "hazard_class": "9", "hazard_class_description": "Miscellaneous Dangerous Goods", "packing_group": "II", "erg_guide": "147", "placard_required": "CLASS 9"}, "delivery_stop": 3},
    {"line_id": "LI-010", "description": "304 Stainless Steel Weld Neck Flanges, 6-inch, 150 lb", "nmfc_code": "170710", "freight_class": 65, "pieces": 4, "package_type": "Pallet", "weight_lbs": 2680, "dimensions_inches": "48 x 40 x 18", "hazmat": false, "delivery_stop": 1},
    {"line_id": "LI-011", "description": "Molded Rubber Gasket Sets, EPDM, assorted sizes", "nmfc_code": "166240", "freight_class": 77.5, "pieces": 2, "package_type": "Carton", "weight_lbs": 190, "dimensions_inches": "24 x 18 x 18", "hazmat": false, "delivery_stop": 1},
    {"line_id": "LI-012", "description": "6063-T5 Aluminum Extrusions, custom U-channel profile, 12-ft", "nmfc_code": "011580", "freight_class": 70, "pieces": 3, "package_type": "Bundle", "weight_lbs": 2580, "dimensions_inches": "144 x 18 x 18", "hazmat": false, "delivery_stop": 3}
  ],
  "shipment_summary": {
    "total_line_items": 12,
    "total_pieces": 47,
    "total_pallets": 12,
    "total_weight_lbs": 18470,
    "hazmat_items_count": 3
  }
}
JSONEOF
chown ga:ga /home/ga/Documents/shipment_data.json
chmod 644 /home/ga/Documents/shipment_data.json

# 4. Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 5. Launch OpenOffice Writer so the agent starts with a blank slate
# Kill any existing instances first
pkill -f soffice 2>/dev/null || true
sleep 2

# Start Writer
echo "Starting OpenOffice Writer..."
su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
sleep 5

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "OpenOffice"; then
        echo "Writer window found"
        # Maximize
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="