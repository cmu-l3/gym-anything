#!/bin/bash
# Setup script for ejection_delay_tuning task
# Copies simple_model_rocket.ork, injects E16, F67, G40 with bad delays

echo "=== Setting up ejection_delay_tuning task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/zipper_prevention.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Use example simple model rocket if source data is missing
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
fi

cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Clean up any residual fixed ork files or reports
rm -f "$ROCKETS_DIR/zipper_prevention_fixed.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/delay_report.txt" 2>/dev/null || true

# Inject E16, F67, G40 configurations with bad delays
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/zipper_prevention.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# 1. Clear existing flight configs
for fc in list(root.findall('flightconfiguration')):
    root.remove(fc)

configs = [
    ('config_E16', 'Estes E16 Flight', 'Estes', 'E16', '15.0'),
    ('config_F67', 'AeroTech F67 Flight', 'AeroTech', 'F67', '14.0'),
    ('config_G40', 'AeroTech G40 Flight', 'AeroTech', 'G40', '0.0')
]

for cid, name, mfg, desig, delay in configs:
    fc = ET.SubElement(root, 'flightconfiguration', {'configid': cid})
    name_el = ET.SubElement(fc, 'name')
    name_el.text = name

# 2. Find parachute and explicitly set deployevent to ejectioncharge
for para in root.iter('parachute'):
    de = para.find('deployevent')
    if de is not None:
        de.text = 'ejectioncharge'
    else:
        de = ET.SubElement(para, 'deployevent')
        de.text = 'ejectioncharge'
    
    # Also set altitude to 0 to prevent accidental usage
    da = para.find('deployaltitude')
    if da is not None:
        da.text = '0.0'

# 3. Find motor mount and inject motors
mm = None
for comp in root.iter():
    if comp.tag == 'motormount' or comp.find('motormount') is not None:
        mm = comp if comp.tag == 'motormount' else comp.find('motormount')
        break

if mm is None:
    for bt in root.iter('bodytube'):
        mm = ET.SubElement(bt, 'motormount')
        break

if mm is not None:
    for m in list(mm.findall('motor')):
        mm.remove(m)
    for ic in list(mm.findall('ignitionconfiguration')):
        mm.remove(ic)

    for cid, name, mfg, desig, delay in configs:
        motor = ET.SubElement(mm, 'motor', {'configid': cid})
        mfg_el = ET.SubElement(motor, 'manufacturer')
        mfg_el.text = mfg
        desig_el = ET.SubElement(motor, 'designation')
        desig_el.text = desig
        delay_el = ET.SubElement(motor, 'delay')
        delay_el.text = delay

# 4. Replace simulations with our own outdated ones
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in list(sims_elem.findall('simulation')):
        sims_elem.remove(sim)
else:
    sims_elem = ET.SubElement(root, 'simulations')

for cid, name, mfg, desig, delay in configs:
    sim = ET.SubElement(sims_elem, 'simulation', {'status': 'outdated'})
    sname = ET.SubElement(sim, 'name')
    sname.text = f"Sim for {desig}"
    conds = ET.SubElement(sim, 'conditions')
    cond_cid = ET.SubElement(conds, 'configid')
    cond_cid.text = cid

# Rewrite XML
modified_xml = ET.tostring(root, encoding='unicode', xml_declaration=False)
modified_xml_bytes = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + modified_xml).encode('utf-8')

with zipfile.ZipFile(ork_path, 'r') as zin:
    with zipfile.ZipFile(tmp_path, 'w', zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename == 'rocket.ork':
                zout.writestr(item, modified_xml_bytes)
            else:
                zout.writestr(item, zin.read(item.filename))

os.replace(tmp_path, ork_path)
PYEOF

if [ $? -ne 0 ]; then
    echo "FATAL: Python setup failed"
    exit 1
fi

# Record ground truth and timestamp
echo "task_start_ts=$(date +%s)" > /tmp/ejection_delay_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the modified rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/ejection_delay_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== ejection_delay_tuning task setup complete ==="