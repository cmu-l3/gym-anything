#!/bin/bash
echo "=== Exporting dihybrid_punnett_generator task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/punnett_task_end.png" 2>/dev/null || true

# We will run a Python script to do the complex logic and dynamic execution
python3 << 'PYEOF' > /tmp/punnett_result.json
import json
import os
import re
import subprocess

result = {
    "script_exists": False,
    "html_exists": False,
    "html_structure": False,
    "initial_RrYy_count": 0,
    "initial_rryy_count": 0,
    "initial_invalid_alleles": 0,
    "dynamic_execution_success": False,
    "dynamic_TtGg_count": 0,
    "dynamic_ttgg_count": 0,
    "dynamic_ttGg_count": 0,
    "dynamic_Ttgg_count": 0,
    "dynamic_invalid_TT_count": 0,
    "error": None
}

script_path = "/home/ga/Documents/punnett_generator.py"
html_path = "/home/ga/Documents/punnett_square.html"

try:
    if os.path.exists(script_path):
        result["script_exists"] = True

    if os.path.exists(html_path):
        result["html_exists"] = True
        with open(html_path, "r", encoding="utf-8", errors="ignore") as f:
            html = f.read()
        
        has_table = "<table" in html.lower()
        has_th = "<th" in html.lower()
        has_td = "<td" in html.lower()
        result["html_structure"] = has_table and has_th and has_td
        
        # Strip HTML tags
        text = re.sub(r'<[^>]+>', ' ', html)
        
        result["initial_RrYy_count"] = len(re.findall(r'\bRrYy\b', text))
        result["initial_rryy_count"] = len(re.findall(r'\brryy\b', text))
        
        # Check for incorrect alleles like rR, yY, or wrong gene order [Yy][Yy][Rr][Rr]
        invalid_matches = re.findall(r'rR', text) + re.findall(r'yY', text) + re.findall(r'[Yy][Yy][Rr][Rr]', text)
        result["initial_invalid_alleles"] = len(invalid_matches)

    # Dynamic execution test (Anti-gaming & algorithmic correctness check)
    if result["script_exists"]:
        # Delete old html to ensure new one is generated
        if os.path.exists(html_path):
            os.remove(html_path)
            
        # Run with unseen arguments TtGg ttgg
        cmd = ["sudo", "-u", "ga", "python3", script_path, "TtGg", "ttgg"]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        
        if os.path.exists(html_path):
            result["dynamic_execution_success"] = True
            with open(html_path, "r", encoding="utf-8", errors="ignore") as f:
                dyn_html = f.read()
                
            dyn_text = re.sub(r'<[^>]+>', ' ', dyn_html)
            
            result["dynamic_TtGg_count"] = len(re.findall(r'\bTtGg\b', dyn_text))
            result["dynamic_ttgg_count"] = len(re.findall(r'\bttgg\b', dyn_text))
            result["dynamic_ttGg_count"] = len(re.findall(r'\bttGg\b', dyn_text))
            result["dynamic_Ttgg_count"] = len(re.findall(r'\bTtgg\b', dyn_text))
            
            # Check for TT or GG which shouldn't exist in TtGg x ttgg
            result["dynamic_invalid_TT_count"] = len(re.findall(r'\bTT[A-Za-z]{2}\b', dyn_text)) + len(re.findall(r'\b[A-Za-z]{2}GG\b', dyn_text))
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/punnett_result.json
echo "Result saved to /tmp/punnett_result.json"
cat /tmp/punnett_result.json
echo "=== Export complete ==="