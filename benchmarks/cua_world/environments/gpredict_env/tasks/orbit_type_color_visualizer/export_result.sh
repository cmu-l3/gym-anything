#!/bin/bash
# Export script for orbit_type_color_visualizer task
echo "=== Exporting orbit_type_color_visualizer result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot before closing
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Cleanly close GPredict so it flushes configuration to disk
echo "Closing GPredict cleanly..."
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -c "Gpredict" 2>/dev/null || true
sleep 3
pkill -x gpredict 2>/dev/null || true
sleep 1

# Use Python to safely parse the INI-like GPredict files and export to JSON
cat << 'EOF' > /tmp/export_parser.py
import json
import os
import re

result = {
    "qth_exists": False,
    "qth_mtime": 0,
    "lat": "", "lon": "", "alt": "",
    "mod_exists": False,
    "mod_mtime": 0,
    "qthfile": "", "layout": "", "satellites": "",
    "colors": {}
}

qth_path = "/home/ga/.config/Gpredict/Purdue_Lab.qth"
mod_path = "/home/ga/.config/Gpredict/modules/Orbit_Types.mod"

if os.path.exists(qth_path):
    result["qth_exists"] = True
    result["qth_mtime"] = os.path.getmtime(qth_path)
    try:
        with open(qth_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        m_lat = re.search(r'(?i)^LAT\s*=\s*(.+)$', content, re.M)
        m_lon = re.search(r'(?i)^LON\s*=\s*(.+)$', content, re.M)
        m_alt = re.search(r'(?i)^ALT\s*=\s*(.+)$', content, re.M)
        if m_lat: result["lat"] = m_lat.group(1).strip()
        if m_lon: result["lon"] = m_lon.group(1).strip()
        if m_alt: result["alt"] = m_alt.group(1).strip()
    except Exception as e:
        pass

if os.path.exists(mod_path):
    result["mod_exists"] = True
    result["mod_mtime"] = os.path.getmtime(mod_path)
    try:
        with open(mod_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        m_qth = re.search(r'(?i)^QTHFILE\s*=\s*(.+)$', content, re.M)
        m_lay = re.search(r'(?i)^LAYOUT\s*=\s*(.+)$', content, re.M)
        m_sat = re.search(r'(?i)^SATELLITES\s*=\s*(.+)$', content, re.M)
        if m_qth: result["qthfile"] = m_qth.group(1).strip()
        if m_lay: result["layout"] = m_lay.group(1).strip()
        if m_sat: result["satellites"] = m_sat.group(1).strip()

        for sat in ["25544", "33591", "43013"]:
            # Find section [Sat_X] and extract COLOR=...
            pattern = r'\[Sat_' + sat + r'\][^\[]*?(?i:COLOR)\s*=\s*([^\n\r]+)'
            m_color = re.search(pattern, content)
            if m_color:
                result["colors"][sat] = m_color.group(1).strip()
    except Exception as e:
        pass

with open("/tmp/orbit_task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/export_parser.py
chmod 666 /tmp/orbit_task_result.json

echo "Result saved to /tmp/orbit_task_result.json:"
cat /tmp/orbit_task_result.json
echo "=== Export complete ==="