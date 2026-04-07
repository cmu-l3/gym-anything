#!/usr/bin/env python3
"""Verifier for find_replace_srs_text task.

Criteria:
1. SRS file must have been modified after task start (Anti-gaming).
2. "sensor" count in SRS text must be 0.
3. "detector" count must equal (Initial "detector" + Initial "sensor").
4. VLM verification of the final state/trajectory.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Adjust import path for gym_anything environment
import sys
# Assuming gym_anything is in the python path or relative
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/Mock for local testing without the framework
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_find_replace_srs_text(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result Data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract metrics
    initial = result.get("initial", {})
    final = result.get("final", {})
    file_modified = result.get("file_modified", False)
    
    init_sensor = initial.get("sensor_count", 0)
    init_detector = initial.get("detector_count", 0)
    final_sensor = final.get("final_sensor_count", -1)
    final_detector = final.get("final_detector_count", -1)
    
    expected_detector = init_detector + init_sensor

    score = 0
    feedback_parts = []
    
    # CRITERION 1: File Modification (10 pts)
    # The agent must actually save the project
    if file_modified:
        score += 10
        feedback_parts.append("Project saved successfully")
    else:
        feedback_parts.append("Project NOT saved (file timestamp unchanged)")

    # CRITERION 2: "Sensor" Elimination (40 pts)
    if final_sensor == 0:
        score += 40
        feedback_parts.append("All 'sensor' terms removed")
    elif final_sensor > 0:
        # Partial credit: if they removed some but not all
        removed = init_sensor - final_sensor
        if removed > 0:
            partial = int(20 * (removed / init_sensor))
            score += partial
            feedback_parts.append(f"Partial replacement: {final_sensor} 'sensor' terms remaining")
        else:
            feedback_parts.append(f"No 'sensor' terms replaced ({final_sensor} remaining)")
    else:
        feedback_parts.append("Error reading final sensor count")

    # CRITERION 3: "Detector" Addition (30 pts)
    # We verify that 'sensor' became 'detector', not just deleted
    if final_detector == expected_detector:
        score += 30
        feedback_parts.append("Target term count matches expectation")
    elif final_detector > init_detector:
        # Some were added, maybe not all?
        # Or maybe they added extra?
        diff = final_detector - expected_detector
        if diff == 0:
            pass # Handled above
        elif diff < 0:
            # Missing some detectors (maybe deleted lines?)
            score += 15
            feedback_parts.append(f"Missing {abs(diff)} 'detector' terms")
        else:
            # Too many detectors?
            score += 25
            feedback_parts.append(f"Extra 'detector' terms found (+{diff})")
    else:
        feedback_parts.append("No new 'detector' terms found")

    # CRITERION 4: VLM Verification (20 pts)
    # Check if the document is visible and looks correct
    frames = sample_trajectory_frames(traj, n=3)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        images = frames + [final_shot]
        prompt = """
        Review these screenshots of the ReqView application.
        1. Is the SRS document (requirements grid) visible in the main view?
        2. Can you see any requirement text containing the word 'detector'?
        3. Is the 'Find and Replace' dialog visible (it should be closed at the end)?
        
        Return JSON:
        {
            "srs_visible": boolean,
            "detector_visible": boolean,
            "dialog_closed": boolean
        }
        """
        vlm_res = query_vlm(images=images, prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("srs_visible"):
                score += 10
                feedback_parts.append("SRS document visible")
            if parsed.get("detector_visible"):
                score += 10
                feedback_parts.append("Visual confirmation of 'detector'")
    else:
        feedback_parts.append("No screenshots available for VLM")

    # Final Pass Logic
    # Must have saved, cleared all sensors, and have roughly correct detectors
    passed = (file_modified and final_sensor == 0 and score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "init_sensor": init_sensor,
            "final_sensor": final_sensor,
            "init_detector": init_detector,
            "final_detector": final_detector,
            "expected_detector": expected_detector
        }
    }