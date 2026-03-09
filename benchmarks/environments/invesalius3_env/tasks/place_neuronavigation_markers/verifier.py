#!/usr/bin/env python3
"""
Verifier for place_neuronavigation_markers task.

Scoring Criteria (100 pts total):
1. [20 pts] Report file exists and was created during task.
2. [20 pts] Report contains at least 3 valid coordinate entries.
3. [20 pts] Coordinates are spatially distinct (pairwise distance > 20mm).
4. [20 pts] Project file (.inv3) exists and is a valid archive.
5. [20 pts] VLM Verification: Agent followed workflow (slices, markers visible).

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_distance(p1, p2):
    return math.sqrt((p1['x'] - p2['x'])**2 + (p1['y'] - p2['y'])**2 + (p1['z'] - p2['z'])**2)

def verify_place_neuronavigation_markers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: Report File (20 pts) ---
    if result.get('report_exists') and result.get('report_created_during_task'):
        score += 20
        feedback.append("Report file created successfully.")
    else:
        feedback.append("Report file missing or not created during task.")

    # --- Criterion 2: Marker Count (20 pts) ---
    markers = result.get('markers', [])
    valid_count = len(markers)
    if valid_count >= 3:
        score += 20
        feedback.append(f"Found {valid_count} markers in report.")
    elif valid_count > 0:
        score += 10
        feedback.append(f"Found only {valid_count}/3 markers.")
    else:
        feedback.append("No valid coordinates found in report.")

    # --- Criterion 3: Spatial Distinctness (20 pts) ---
    # Prevents entering the same point 3 times or trivial (0,0,0) points
    distinct = True
    if len(markers) >= 2:
        for i in range(len(markers)):
            for j in range(i + 1, len(markers)):
                dist = calculate_distance(markers[i], markers[j])
                if dist < 20.0:  # mm
                    distinct = False
                    feedback.append(f"Markers '{markers[i]['name']}' and '{markers[j]['name']}' are too close ({dist:.1f}mm).")
        
        # Also check for trivial origin coordinates
        for m in markers:
            if abs(m['x']) < 1.0 and abs(m['y']) < 1.0 and abs(m['z']) < 1.0:
                distinct = False
                feedback.append(f"Marker '{m['name']}' is at origin (0,0,0), which is unlikely.")

    if distinct and valid_count >= 3:
        score += 20
        feedback.append("Markers are spatially distinct.")
    elif valid_count < 3:
        pass # Already penalized above
    else:
        feedback.append("Markers are not distinct enough.")

    # --- Criterion 4: Project File (20 pts) ---
    if result.get('project_exists') and result.get('project_created_during_task'):
        if result.get('project_valid_archive'):
            score += 20
            feedback.append("Project file saved and is valid.")
        else:
            score += 10
            feedback.append("Project file saved but is not a valid archive.")
    else:
        feedback.append("Project file not saved.")

    # --- Criterion 5: VLM Verification (20 pts) ---
    # Check if the agent actually used the interface
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames and query_vlm:
        prompt = """
        You are verifying a medical software task in InVesalius.
        The user should have:
        1. Navigated through slice views (axial/coronal/sagittal).
        2. Placed 'fiducial markers' or points (often look like colored crosses or dots on the scan).
        3. Potentially opened a dialog to see coordinates.

        Examine the screenshots. Do you see evidence of:
        - Navigation (different slices shown)?
        - Markers/Points placed on the images?
        - Interaction with the coordinate system?

        Answer 'YES' or 'NO' and provide a brief reason.
        """
        
        vlm_response = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if vlm_response.get('success'):
            content = vlm_response.get('parsed', {}).get('response', vlm_response.get('content', '')).upper()
            if "YES" in content:
                score += 20
                feedback.append("VLM verification passed: Workflow observed.")
            else:
                feedback.append("VLM verification warning: No clear evidence of marker placement in screenshots.")
        else:
            # Fallback if VLM fails: give points if file output is very good
            if score >= 60:
                score += 20
                feedback.append("VLM unavailable, assumed pass based on strong file evidence.")
    else:
        # No frames available?
        if score >= 60:
             score += 20
             feedback.append("No trajectory frames, skipping VLM check.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"markers": markers}
    }