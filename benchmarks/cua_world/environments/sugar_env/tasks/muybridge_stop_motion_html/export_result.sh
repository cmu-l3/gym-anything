#!/bin/bash
echo "=== Exporting muybridge_stop_motion_html task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/muybridge_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/muybridge_task_start_ts 2>/dev/null || echo "0")
GIF_FILE="/home/ga/Documents/horse_motion.gif"
HTML_FILE="/home/ga/Documents/cinema_history.html"

# Use Python to analyze files safely
python3 << PYEOF > /tmp/muybridge_analysis.json
import json
import os
import re
import subprocess

task_start = $TASK_START
gif_file = "$GIF_FILE"
html_file = "$HTML_FILE"

result = {
    "gif_exists": False,
    "gif_modified": False,
    "gif_frames": 0,
    "gif_width": 0,
    "gif_delay": 0,
    "html_exists": False,
    "html_modified": False,
    "html_embeds_img": False,
    "html_has_muybridge": False,
    "html_has_1878": False,
    "html_has_bg_color": False,
    "html_has_fg_color": False,
    "browse_running": False
}

# Check GIF
if os.path.isfile(gif_file):
    result["gif_exists"] = True
    if os.path.getmtime(gif_file) > task_start:
        result["gif_modified"] = True
        
    try:
        # Get frame count
        frames_out = subprocess.check_output(['identify', '-format', '%n\n', gif_file], stderr=subprocess.DEVNULL).decode('utf-8')
        result["gif_frames"] = int(frames_out.split('\n')[0].strip())
        
        # Get width
        width_out = subprocess.check_output(['identify', '-format', '%w\n', gif_file], stderr=subprocess.DEVNULL).decode('utf-8')
        result["gif_width"] = int(width_out.split('\n')[0].strip())
        
        # Get delay (10 ticks = 100ms)
        delay_out = subprocess.check_output(['identify', '-format', '%T\n', gif_file], stderr=subprocess.DEVNULL).decode('utf-8')
        result["gif_delay"] = int(delay_out.split('\n')[0].strip())
    except Exception:
        pass

# Check HTML
if os.path.isfile(html_file):
    result["html_exists"] = True
    if os.path.getmtime(html_file) > task_start:
        result["html_modified"] = True
        
    try:
        with open(html_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        # Check image embed
        if re.search(r'<img[^>]+src=[\'"](?:[^"\'/]+/)*horse_motion\.gif[\'"]', content, re.IGNORECASE):
            result["html_embeds_img"] = True
            
        # Check keywords
        if re.search(r'\bmuybridge\b', content, re.IGNORECASE):
            result["html_has_muybridge"] = True
        if '1878' in content:
            result["html_has_1878"] = True
            
        # Check CSS hex colors
        if re.search(r'#333333', content, re.IGNORECASE):
            result["html_has_bg_color"] = True
        if re.search(r'#ffffff', content, re.IGNORECASE):
            result["html_has_fg_color"] = True
    except Exception:
        pass

# Check if Browse activity is running
try:
    proc_out = subprocess.check_output(['pgrep', '-f', 'sugar-browse-activity'], stderr=subprocess.DEVNULL)
    if proc_out:
        result["browse_running"] = True
except subprocess.CalledProcessError:
    pass

with open('/tmp/muybridge_analysis.json', 'w') as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/muybridge_analysis.json
echo "Result saved to /tmp/muybridge_analysis.json"
cat /tmp/muybridge_analysis.json
echo "=== Export complete ==="