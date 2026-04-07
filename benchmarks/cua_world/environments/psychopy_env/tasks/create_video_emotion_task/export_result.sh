#!/bin/bash
echo "=== Exporting create_video_emotion_task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Run analysis script
python3 << 'PYEOF'
import json
import os
import sys
import datetime
import csv
import xml.etree.ElementTree as ET

EXP_FILE = "/home/ga/PsychoPyExperiments/emotion_task/emotion_rating.psyexp"
COND_FILE = "/home/ga/PsychoPyExperiments/emotion_task/video_conditions.csv"
RESULT_FILE = "/tmp/video_emotion_result.json"
ASSETS_DIR = "/home/ga/PsychoPyExperiments/emotion_task"

results = {
    "exp_exists": False,
    "csv_exists": False,
    "assets_copied": False,
    "valid_xml": False,
    "has_movie_component": False,
    "movie_uses_variable": False,
    "slider_count": 0,
    "has_valence_slider": False,
    "has_arousal_slider": False,
    "has_loop": False,
    "loop_uses_csv": False,
    "csv_valid": False,
    "csv_row_count": 0,
    "csv_has_required_cols": False,
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat()
}

# Read task start time and nonce
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# Check Experiment File
if os.path.isfile(EXP_FILE):
    results["exp_exists"] = True
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            results["valid_xml"] = True
        
        # Check Components
        routines = root.findall(".//Routine")
        for routine in routines:
            for comp in routine:
                comp_type = comp.tag
                # Movie Component
                if "Movie" in comp_type:
                    results["has_movie_component"] = True
                    # Check if movie file param uses variable ($)
                    for param in comp:
                        if param.get("name") == "movie" and "$" in param.get("val", ""):
                            results["movie_uses_variable"] = True
                
                # Slider Component
                if "Slider" in comp_type:
                    results["slider_count"] += 1
                    name = comp.get("name", "").lower()
                    # Check labels/name for valence/arousal intent
                    if "valence" in name:
                        results["has_valence_slider"] = True
                    if "arousal" in name:
                        results["has_arousal_slider"] = True
                    # Also check params for labels if name is generic
                    for param in comp:
                        if param.get("name") == "labels":
                            val = param.get("val", "").lower()
                            if "positive" in val or "negative" in val:
                                results["has_valence_slider"] = True
                            if "calm" in val or "excited" in val:
                                results["has_arousal_slider"] = True

        # Check Loop
        loops = root.findall(".//LoopInitiator")
        if loops:
            results["has_loop"] = True
            for loop in loops:
                for param in loop:
                    if param.get("name") == "conditionsFile":
                        val = param.get("val", "")
                        if "video_conditions.csv" in val:
                            results["loop_uses_csv"] = True

    except Exception as e:
        print(f"XML Parse Error: {e}", file=sys.stderr)

# Check CSV File
if os.path.isfile(COND_FILE):
    results["csv_exists"] = True
    try:
        with open(COND_FILE, 'r') as f:
            reader = csv.DictReader(f)
            headers = [h.lower() for h in (reader.fieldnames or [])]
            rows = list(reader)
            results["csv_row_count"] = len(rows)
            
            if "video_file" in headers and "emotion" in headers:
                results["csv_has_required_cols"] = True
    except Exception as e:
        print(f"CSV Parse Error: {e}", file=sys.stderr)

# Check Assets Copied
if os.path.isdir(ASSETS_DIR):
    videos = [f for f in os.listdir(ASSETS_DIR) if f.endswith(".mp4")]
    if len(videos) >= 3:
        results["assets_copied"] = True

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)
os.chmod(RESULT_FILE, 0o666)
PYEOF

cat /tmp/video_emotion_result.json
echo "=== Export complete ==="