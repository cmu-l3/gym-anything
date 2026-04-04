#!/usr/bin/env python3
"""
Verifier for generate_adaptive_icons task.

Scoring Breakdown (100 pts total):
1. Asset Generation (40 pts):
   - ic_launcher.xml (anydpi) exists and modified: 10 pts
   - ic_launcher_round.xml (anydpi) exists and modified: 10 pts
   - ic_launcher_foreground.xml exists: 10 pts
   - ic_launcher_background.xml exists: 10 pts

2. Background Color (30 pts):
   - ic_launcher_background.xml contains #263238: 30 pts

3. Foreground Validity (20 pts):
   - Foreground XML contains vector path data (implies successful SVG conversion): 20 pts

4. Build Integrity (10 pts):
   - 'gradlew mergeDebugResources' passes: 10 pts

Pass Threshold: 70 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_adaptive_icons(traj, env_info, task_info):
    """Verify the generated Android adaptive icons."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Asset Generation (40 pts)
    # We require them to be 'modified' (created/updated during task) to prevent existing files passing
    assets_score = 0
    
    if result.get("status_adaptive_xml") == "modified":
        assets_score += 10
    elif result.get("status_adaptive_xml") == "exists_old":
        feedback.append("ic_launcher.xml exists but was not updated.")
    else:
        feedback.append("ic_launcher.xml missing.")

    if result.get("status_round_xml") == "modified":
        assets_score += 10
    
    # Foreground/Background files might be new or overwritten
    if result.get("status_foreground") in ["modified", "exists_old"]: 
        # "exists_old" is unlikely for foreground if it didn't exist before, but acceptable if they overwrote same name
        assets_score += 10
    else:
        feedback.append("Foreground drawable missing.")

    if result.get("status_background") in ["modified", "exists_old"]:
        assets_score += 10
    else:
        feedback.append("Background value file missing.")
        
    score += assets_score
    feedback.append(f"Assets created: {assets_score}/40")

    # 2. Background Color (30 pts)
    if result.get("bg_color_found"):
        score += 30
        feedback.append("Background color correct (#263238).")
    else:
        val = result.get("bg_color_value", "none")
        feedback.append(f"Incorrect background color. Found: {val}, Expected: #263238.")

    # 3. Foreground Content (20 pts)
    if result.get("foreground_valid"):
        score += 20
        feedback.append("Foreground vector data valid.")
    else:
        feedback.append("Foreground XML does not look like a valid vector conversion.")

    # 4. Build Integrity (10 pts)
    if result.get("build_success"):
        score += 10
        feedback.append("Resource merge build passed.")
    else:
        feedback.append("Resource merge build failed (invalid XML generated?).")

    # Final tally
    passed = score >= 70 and result.get("bg_color_found") and result.get("status_adaptive_xml") == "modified"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }