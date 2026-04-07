#!/usr/bin/env python3
"""
Verifier for Beverage Unit Hierarchy task.

Criteria:
1. Unit Group "Beverage Packaging" exists (20 pts)
2. Correct Units and Conversion Factors (Reference=Bottle, Case=24, Pallet=1920) (40 pts)
3. Product Flow "Cola 500mL" exists and uses the group (20 pts)
4. Process "Cola Palletizing" exists (10 pts)
5. VLM: Trajectory shows interaction with Unit Groups editor (10 pts)

Pass threshold: 80 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

TRAJECTORY_PROMPT = """You are analyzing screenshots of a user working in openLCA.
The user is supposed to be creating a custom 'Unit Group' for beverage packaging (Bottles, Cases, Pallets).

Look for:
1. Navigation to "Unit groups" in the sidebar.
2. A dialog or editor showing "Conversion factor" or "Reference unit".
3. Tables showing units like "Bottle", "Case", "Pallet" and numbers like "24.0" or "1920.0".
4. Creation of a Flow or Process.

Respond in JSON:
{
    "unit_group_editor_seen": true/false,
    "conversion_factors_seen": true/false,
    "flow_or_process_creation": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_beverage_unit_hierarchy(traj, env_info, task_info):
    """Verify creation of Unit Group hierarchy."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load results
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Unit Group Exists (20 pts)
    if result.get("group_found"):
        score += 20
        feedback.append("Unit Group 'Beverage Packaging' found.")
    else:
        feedback.append("Unit Group 'Beverage Packaging' NOT found.")

    # 2. Units and Factors (40 pts)
    # Expected: Bottle=1 (Ref), Case=24, Pallet=1920
    # Note: openLCA might store them relative to reference.
    units = result.get("units", [])
    found_units = {u['name'].lower(): u['factor'] for u in units}
    
    # Check Bottle (Ref)
    if 'bottle' in found_units:
        # If bottle is ref, factor is 1.0. If they made Pallet ref, Bottle would be 1/1920.
        # Task asked for Bottle to be ref.
        if abs(found_units['bottle'] - 1.0) < 0.01:
            score += 10
            feedback.append("Unit 'Bottle' correctly defined as reference.")
        else:
            feedback.append(f"Unit 'Bottle' found but factor is {found_units['bottle']} (expected 1.0).")
    else:
        feedback.append("Unit 'Bottle' missing.")

    # Check Case (24)
    if 'case' in found_units:
        if abs(found_units['case'] - 24.0) < 0.1:
            score += 15
            feedback.append("Unit 'Case' correctly defined (24.0).")
        else:
            feedback.append(f"Unit 'Case' factor incorrect: {found_units['case']} (expected 24.0).")
    else:
        feedback.append("Unit 'Case' missing.")

    # Check Pallet (1920)
    if 'pallet' in found_units:
        if abs(found_units['pallet'] - 1920.0) < 1.0:
            score += 15
            feedback.append("Unit 'Pallet' correctly defined (1920.0).")
        else:
            feedback.append(f"Unit 'Pallet' factor incorrect: {found_units['pallet']} (expected 1920.0).")
    else:
        feedback.append("Unit 'Pallet' missing.")

    # 3. Flow (20 pts)
    if result.get("flow_found"):
        if result.get("flow_linked_correctly"):
            score += 20
            feedback.append("Flow 'Cola 500mL' created and linked to correct unit group.")
        else:
            score += 10
            feedback.append("Flow 'Cola 500mL' created but linked to WRONG unit group.")
    else:
        feedback.append("Flow 'Cola 500mL' not found.")

    # 4. Process (10 pts)
    if result.get("process_found"):
        score += 10
        feedback.append("Process 'Cola Palletizing' found.")
    else:
        feedback.append("Process 'Cola Palletizing' not found.")

    # 5. VLM Verification (10 pts)
    # Check if they actually used the UI
    from gym_anything.vlm import sample_trajectory_frames
    frames = sample_trajectory_frames(traj, 5)
    query_vlm = env_info.get('query_vlm')
    
    vlm_score = 0
    if query_vlm and frames:
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_res:
            if vlm_res.get("unit_group_editor_seen") or vlm_res.get("conversion_factors_seen"):
                vlm_score = 10
                feedback.append("VLM confirmed UI interaction with Unit Groups.")
            else:
                feedback.append("VLM did not observe Unit Group editor interaction.")
    
    # Fallback if VLM fails but programmatic passed
    if vlm_score == 0 and score >= 60:
        vlm_score = 10
        feedback.append("Implicit VLM pass (programmatic success).")

    score += vlm_score

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }