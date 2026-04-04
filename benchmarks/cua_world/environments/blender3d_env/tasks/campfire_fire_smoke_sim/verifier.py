#!/usr/bin/env python3
"""
Verifier for campfire_fire_smoke_sim task.

SCORING CRITERIA (100 pts total):
1. Domain object exists with GAS type (20 pts)
2. Flow emitter exists (20 pts)
3. Flow emits FIRE or BOTH (10 pts)
4. Domain has Volume Material (15 pts)
5. Resolution >= 32 (10 pts)
6. Frame range ~1-100 (10 pts)
7. File saved & valid (15 pts)

Pass Threshold: 70 pts
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_campfire_sim(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    scene_analysis = result.get("scene_analysis", {})
    file_exists = result.get("file_exists", False)
    file_modified = result.get("file_modified", False)
    
    score = 0
    feedback = []

    # 3. Evaluate Criteria

    # Criterion 7: File Saved & Valid (15 pts)
    # Check modification time to prevent using an old file
    if file_exists and file_modified:
        score += 15
        feedback.append("✅ File saved and modified")
    elif file_exists:
        score += 5
        feedback.append("⚠️ File exists but was not modified during task")
    else:
        feedback.append("❌ File not found")
        # Critical failure if no file
        return {"passed": False, "score": 0, "feedback": "No output file found. Task failed.", "details": result}

    # Criterion 1: Domain Object (20 pts)
    if scene_analysis.get("domain_found"):
        if scene_analysis.get("domain_type_gas"):
            score += 20
            feedback.append("✅ Gas Domain found")
        else:
            score += 10
            feedback.append("⚠️ Domain found but not set to GAS type")
    else:
        feedback.append("❌ No Domain object found")

    # Criterion 2: Flow Emitter (20 pts)
    if scene_analysis.get("flow_found"):
        score += 20
        feedback.append("✅ Flow emitter found")
    else:
        feedback.append("❌ No Flow emitter found")

    # Criterion 3: Flow Type Fire/Both (10 pts)
    if scene_analysis.get("flow_type_fire"):
        score += 10
        feedback.append("✅ Flow set to Fire/Both")
    elif scene_analysis.get("flow_found"):
        feedback.append("⚠️ Flow exists but set to Smoke only (expected Fire)")
    
    # Criterion 4: Volume Material (15 pts)
    if scene_analysis.get("volume_material_found"):
        score += 15
        feedback.append("✅ Volume material assigned to domain")
    else:
        feedback.append("❌ No Volume material found on domain (smoke won't render)")

    # Criterion 5: Resolution (10 pts)
    res = scene_analysis.get("domain_resolution", 0)
    if res >= 32:
        score += 10
        feedback.append(f"✅ Resolution sufficient ({res})")
    elif res > 0:
        score += 5
        feedback.append(f"⚠️ Resolution too low ({res} < 32)")
    else:
        feedback.append("❌ Resolution check failed")

    # Criterion 6: Frame Range (10 pts)
    # Target 1-100, allow some tolerance
    start = scene_analysis.get("frame_start", 1)
    end = scene_analysis.get("frame_end", 250)
    
    range_ok = (abs(start - 1) <= 5) and (abs(end - 100) <= 20)
    if range_ok:
        score += 10
        feedback.append(f"✅ Frame range correct ({start}-{end})")
    else:
        feedback.append(f"❌ Frame range incorrect (Found {start}-{end}, expected ~1-100)")

    # 4. Final Verdict
    passed = (score >= 70) and scene_analysis.get("domain_found") and scene_analysis.get("flow_found")
    
    final_feedback = f"Score: {score}/100. " + "; ".join(feedback)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback,
        "details": result
    }