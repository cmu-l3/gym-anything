#!/bin/bash
set -e
echo "=== Setting up Build Assembly BOM task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create ground truth directory (hidden from agent)
mkdir -p /var/lib/wps_ground_truth
chmod 700 /var/lib/wps_ground_truth

# 1. Create the source CSV with real Arduino Uno-style components and pricing
cat > /home/ga/Documents/pcb_components.csv << 'CSVEOF'
Reference,Value,Package,Manufacturer_PN,Description,Category,Quantity,Unit_Cost_USD
R1,10K,0402,RC0402FR-0710KL,Resistor 10K Ohm 1% 1/16W,Resistors,1,0.01
R2,10K,0402,RC0402FR-0710KL,Resistor 10K Ohm 1% 1/16W,Resistors,1,0.01
R3,1K,0402,RC0402FR-071KL,Resistor 1K Ohm 1% 1/16W,Resistors,1,0.01
R4,1K,0402,RC0402FR-071KL,Resistor 1K Ohm 1% 1/16W,Resistors,1,0.01
R5,100K,0402,RC0402FR-07100KL,Resistor 100K Ohm 1% 1/16W,Resistors,1,0.01
R6,4.7K,0402,RC0402FR-074K7L,Resistor 4.7K Ohm 1% 1/16W,Resistors,1,0.01
R7,22,0402,RC0402FR-0722RL,Resistor 22 Ohm 1% 1/16W,Resistors,2,0.01
R8,1M,0402,RC0402FR-071ML,Resistor 1M Ohm 1% 1/16W,Resistors,1,0.01
R9,470,0402,RC0402FR-07470RL,Resistor 470 Ohm 1% 1/16W,Resistors,3,0.01
R10,330,0402,RC0402FR-07330RL,Resistor 330 Ohm 1% 1/16W,Resistors,1,0.01
C1,100nF,0402,CL05B104KO5NNNC,MLCC 100nF 16V X7R,Capacitors,10,0.02
C2,22pF,0402,CL05C220JB5NNNC,MLCC 22pF 50V C0G,Capacitors,2,0.01
C3,1uF,0402,CL05A105KA5NQNC,MLCC 1uF 25V X5R,Capacitors,4,0.03
C4,10uF,0805,CL21A106KAYNNNE,MLCC 10uF 25V X5R,Capacitors,3,0.05
C5,4.7uF,0603,CL10A475KQ8NNNC,MLCC 4.7uF 6.3V X5R,Capacitors,2,0.04
C6,47uF,Radial-5mm,UVR1V470MDD1TD,Electrolytic 47uF 35V,Capacitors,2,0.12
C7,100uF,Radial-6.3mm,UVR1C101MED1TD,Electrolytic 100uF 16V,Capacitors,1,0.15
C8,220pF,0402,CL05C221JB5NNNC,MLCC 220pF 50V C0G,Capacitors,2,0.01
U1,ATmega328P,TQFP-32,ATMEGA328P-AU,8-bit AVR Microcontroller 32KB Flash,ICs,1,2.56
U2,ATmega16U2,TQFP-32,ATMEGA16U2-AU,8-bit AVR USB Microcontroller,ICs,1,2.84
U3,LM358,SOIC-8,LM358DR,Dual Op-Amp General Purpose,ICs,1,0.42
U4,NCP1117ST33,SOT-223,NCP1117ST33T3G,LDO Regulator 3.3V 1A,ICs,1,0.45
U5,uA7805,D2PAK,UA7805CKCS,Linear Regulator 5V 1.5A,ICs,1,0.58
U6,FT232RL,SSOP-28,FT232RL-REEL,USB to UART Bridge IC,ICs,1,4.50
U7,74HC595,SOIC-16,SN74HC595DR,8-bit Shift Register,ICs,2,0.38
U8,MCP2515,SOIC-18,MCP2515-I/SO,CAN Bus Controller SPI,ICs,1,1.95
J1,USB-B,USB-B-TH,UE27AC54100,USB Type-B Receptacle Through-Hole,Connectors,1,0.65
J2,DC-Barrel,DC-Jack-2.1mm,PJ-002A,DC Power Jack 2.1mm Center-Positive,Connectors,1,0.72
J3,Header-6pin,Pin-Header-2.54mm,61300611121,Male Pin Header 1x6 2.54mm,Connectors,2,0.18
J4,Header-8pin,Pin-Header-2.54mm,61300811121,Male Pin Header 1x8 2.54mm,Connectors,2,0.24
J5,Header-10pin,Pin-Header-2.54mm,61301011121,Male Pin Header 1x10 2.54mm,Connectors,1,0.30
J6,ICSP-Header,Pin-Header-2x3,10129381-906002BLF,Male Pin Header 2x3 2.54mm,Connectors,2,0.35
J7,Screw-Terminal-2P,5mm-Pitch,1729018,Screw Terminal Block 2-Position,Connectors,2,0.48
J8,RJ45,RJ45-TH,RJHSE-5080,RJ45 Modular Jack with LEDs,Connectors,1,1.25
Y1,16MHz,HC49,FOXSLF/160-20,Crystal 16MHz 20pF HC49/US,Crystals_Oscillators,2,0.35
Y2,8MHz,HC49,FOXSLF/080-20,Crystal 8MHz 20pF HC49/US,Crystals_Oscillators,1,0.32
D1,1N4148,SOD-323,1N4148WS,Switching Diode 100V 150mA,Diodes_LEDs,2,0.03
D2,1N5819,SMA,SS14,Schottky Diode 40V 1A,Diodes_LEDs,1,0.12
D3,LED-Green,0805,APTD2012LCGCK,LED Green 0805 2.0V 20mA,Diodes_LEDs,3,0.08
D4,LED-Red,0805,APTD2012LSECK/J3-PF,LED Red 0805 2.0V 20mA,Diodes_LEDs,1,0.08
D5,LED-Yellow,0805,APTD2012LSYCK,LED Yellow 0805 2.1V 20mA,Diodes_LEDs,2,0.08
D6,LED-Blue,0805,APTD2012LVBC/D,LED Blue 0805 3.2V 20mA,Diodes_LEDs,1,0.10
D7,B5819W,SOD-123,B5819W-TP,Schottky Barrier Diode 40V 1A,Diodes_LEDs,2,0.09
Q1,MMBT3904,SOT-23,MMBT3904LT1G,NPN Transistor 40V 200mA,ICs,2,0.05
Q2,MMBT3906,SOT-23,MMBT3906LT1G,PNP Transistor 40V 200mA,ICs,2,0.05
L1,10uH,0805,MLZ2012N100LT000,Ferrite Bead Inductor 10uH 0805,Inductors_Ferrites,1,0.15
L2,BLM18PG,0603,BLM18PG121SN1D,Ferrite Bead 120 Ohm 0603,Inductors_Ferrites,3,0.08
L3,4.7uH,1210,NR3015T4R7M,Power Inductor 4.7uH Shielded 1.3A,Inductors_Ferrites,1,0.45
F1,500mA,1206,0467.500NR,PTC Resettable Fuse 500mA,Inductors_Ferrites,1,0.28
SW1,Tactile,6x6mm,SKQGAFE010,Tactile Switch SPST-NO 6x6mm,Connectors,1,0.15
SW2,DIP-4,DIP-Switch,SDA04H1SBD,4-Position DIP Switch,Connectors,1,0.65
CSVEOF

chown ga:ga /home/ga/Documents/pcb_components.csv

# 2. Compute ground truth values dynamically
python3 << 'PYEOF'
import csv
import json

totals = {}
grand_total = 0.0
total_qty = 0
row_count = 0

with open('/home/ga/Documents/pcb_components.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        row_count += 1
        qty = int(row['Quantity'])
        unit_cost = float(row['Unit_Cost_USD'])
        ext_cost = qty * unit_cost
        cat = row['Category']
        
        total_qty += qty
        grand_total += ext_cost
        
        if cat not in totals:
            totals[cat] = {'total_cost': 0.0, 'total_qty': 0, 'count': 0}
        totals[cat]['total_cost'] += ext_cost
        totals[cat]['total_qty'] += qty
        totals[cat]['count'] += 1

truth = {
    'row_count': row_count,
    'grand_total_cost': round(grand_total, 2),
    'total_quantity': total_qty,
    'categories': {k: {'total_cost': round(v['total_cost'], 2), 'total_qty': v['total_qty'], 'count': v['count']} for k, v in totals.items()},
    'category_names_sorted': sorted(totals.keys())
}

with open('/var/lib/wps_ground_truth/bom_truth.json', 'w') as f:
    json.dump(truth, f, indent=2)

print(f"Ground truth generated: {row_count} rows, {len(totals)} categories, total cost ${grand_total:.2f}")
PYEOF
chmod 600 /var/lib/wps_ground_truth/bom_truth.json

# Remove any previous output to prevent gaming
rm -f /home/ga/Documents/assembly_bom.xlsx

# Ensure clean state for WPS Spreadsheet
pkill -x et 2>/dev/null || true
pkill -f "/office6/et" 2>/dev/null || true
sleep 2

# Launch WPS Spreadsheet
echo "Starting WPS Spreadsheet..."
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et &"
sleep 6

# Dismiss any startup dialogs
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Escape" 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="