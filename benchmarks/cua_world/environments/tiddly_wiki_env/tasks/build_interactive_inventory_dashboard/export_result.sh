#!/bin/bash
echo "=== Exporting build_interactive_inventory_dashboard result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Capture the final state screenshot for VLM and manual review
take_screenshot /tmp/task_final_state.png

# Create a robust Python script to gather the data to avoid bash escaping hell with Wikitext
python3 - << 'PYEOF'
import os
import json
import time
import glob

TIDDLER_DIR = "/home/ga/mywiki/tiddlers"
DASHBOARD_TITLES = [
    "Reagent Inventory.tid",
    "Reagent_Inventory.tid"
]

result = {
    "task_start_time": 0,
    "export_time": time.time(),
    "dashboard_exists": False,
    "dashboard_text": "",
    "dashboard_mtime": 0,
    "reagents_intact": True,
    "reagent_data": {},
    "gui_save_detected": False,
    "screenshot_exists": os.path.exists("/tmp/task_final_state.png")
}

# Get task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        result["task_start_time"] = int(f.read().strip())
except:
    pass

# Locate dashboard tiddler safely (accounting for possible underscore replacements in filenames)
dashboard_path = None
for title in DASHBOARD_TITLES:
    p = os.path.join(TIDDLER_DIR, title)
    if os.path.exists(p):
        dashboard_path = p
        break

# Try insensitive search if exact match fails
if not dashboard_path:
    for f in os.listdir(TIDDLER_DIR):
        if f.lower() == "reagent inventory.tid" or f.lower() == "reagent_inventory.tid":
            dashboard_path = os.path.join(TIDDLER_DIR, f)
            break

if dashboard_path and os.path.exists(dashboard_path):
    result["dashboard_exists"] = True
    result["dashboard_mtime"] = os.path.getmtime(dashboard_path)
    with open(dashboard_path, "r", encoding="utf-8") as f:
        result["dashboard_text"] = f.read()

# Check original reagents to ensure they weren't deleted or horribly mutated
expected_reagents = [
    "Taq DNA Polymerase", "10x TBE Buffer", "Agarose Powder, LE", 
    "1000uL Pipette Tips", "Ethidium Bromide (10mg/mL)", "Nuclease-Free Water"
]

for reagent in expected_reagents:
    # Handle filesystem path sanitization (e.g. forward slash in Ethidium Bromide)
    safe_name = reagent.replace("/", "_") + ".tid"
    path = os.path.join(TIDDLER_DIR, safe_name)
    
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
            # Verify it still has the Reagent tag
            if "tags: Reagent" not in content and "tags: [[Reagent]]" not in content:
                result["reagents_intact"] = False
            
            # Simple scrape of stock level for debugging
            stock = "unknown"
            for line in content.split("\n"):
                if line.startswith("stock_level:"):
                    stock = line.split(":", 1)[1].strip()
            result["reagent_data"][reagent] = stock
    else:
        result["reagents_intact"] = False
        result["reagent_data"][reagent] = "MISSING"

# Check server logs for GUI interaction to prevent terminal/scripting shortcuts
log_path = "/home/ga/tiddlywiki.log"
if os.path.exists(log_path):
    with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
        log_content = f.read().lower()
        if "dispatching 'save' task" in log_content and "reagent inventory" in log_content:
            result["gui_save_detected"] = True

# Write the collected data safely
with open("/tmp/inventory_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/inventory_result.json 2>/dev/null || sudo chmod 666 /tmp/inventory_result.json

echo "Result JSON generated at /tmp/inventory_result.json"
cat /tmp/inventory_result.json
echo "=== Export complete ==="