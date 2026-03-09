#!/usr/bin/env python3
"""
Verifier for create_demographics_section task.
Verifies that the agent correctly customized the LibreHealth EHR layout
by checking database state and VLM trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_demographics_section(traj, env_info, task_info):
    """
    Verify the creation of the RPM demographics section and field.
    """
    # 1. Setup and Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy function missing)"}

    # 2. Retrieve Exported Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Group Created (40 pts)
    if result.get("group_found", False):
        score += 40
        feedback_parts.append("✅ RPM group created")
    else:
        feedback_parts.append("❌ RPM group not found")

    # Criterion 2: Field Created (30 pts)
    # Check if field exists, even if not linked correctly yet
    if result.get("field_found", False):
        score += 30
        feedback_parts.append("✅ Device Serial field created")
    else:
        feedback_parts.append("❌ Device Serial field not found")

    # Criterion 3: Field Linked to Group (20 pts)
    if result.get("field_in_correct_group", False):
        score += 20
        feedback_parts.append("✅ Field linked to RPM group")
    else:
        if result.get("group_found") and result.get("field_found"):
             feedback_parts.append("❌ Field exists but not in RPM group")

    # Criterion 4: Field Type (10 pts)
    if result.get("field_type_correct", False):
        score += 10
        feedback_parts.append("✅ Field type is Text")
    elif result.get("field_found"):
        feedback_parts.append(f"❌ Incorrect field type (Type ID: {result.get('field_data_type')})")

    # 4. VLM Verification (Anti-Gaming & Process Check)
    # Ensure they actually used the Layout Editor UI
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying an agent's work in an EHR system (LibreHealth/OpenEMR).
    The goal was to:
    1. Open the Layout Editor (Administration > Layouts).
    2. Add a new group named "RPM".
    3. Add a field named "Device Serial Number".
    
    Look at these screenshots of the agent's workflow.
    
    Do you see:
    - The "Layouts" or "Demographics" configuration screen?
    - A dialog or form for adding a "New Group" or "New Field"?
    - The text "RPM" or "Device Serial Number" being typed or displayed in the configuration UI?
    
    Return JSON:
    {
      "layout_editor_visible": true/false,
      "editing_actions_observed": true/false,
      "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_passed = False
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("layout_editor_visible") or parsed.get("editing_actions_observed"):
            vlm_passed = True
            feedback_parts.append("✅ VLM verified UI interaction")
        else:
            feedback_parts.append("⚠️ VLM could not confirm Layout Editor usage")
            # If database checks pass but VLM fails, we might deduct points or just warn
            # For this task, database is the gold truth, but we want to ensure no 'magic' SQL injection
            # If perfect DB score, we trust it, but VLM adds confidence.
            
    # 5. Final Result
    passed = score >= 70  # Threshold: Must at least create Group + Field
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }