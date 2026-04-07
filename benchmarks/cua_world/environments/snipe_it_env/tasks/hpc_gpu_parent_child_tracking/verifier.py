#!/usr/bin/env python3
"""Verifier for hpc_gpu_parent_child_tracking task.

Scoring breakdown (100 points):
  C1 (15 pts): Parent asset AI-CHASSIS-01 created successfully
  C2 (15 pts): New child assets GPU-H100-101 and GPU-H100-102 created
  C3 (20 pts): Legacy GPUs GPU-H100-001 & GPU-H100-002 checked in from old chassis
  C4 (30 pts): All 4 GPUs checked out to Asset AI-CHASSIS-01
  C5 (20 pts): AI-CHASSIS-01 checked out to Location Data Center - Rack 42
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/hpc_gpu_parent_child_tracking_result.json"


def verify_hpc_gpu_parent_child_tracking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    rack_location_id = str(result.get("rack_location_id", "0"))
    legacy_server_id = str(result.get("legacy_server_id", "0"))
    
    chassis_01 = result.get("chassis_01", {})
    gpu_101 = result.get("gpu_101", {})
    gpu_102 = result.get("gpu_102", {})
    gpu_001 = result.get("gpu_001", {})
    gpu_002 = result.get("gpu_002", {})

    # --- Do-nothing gate ---
    if not chassis_01.get("found") and not gpu_101.get("found") and str(gpu_001.get("assigned_to", "0")) == legacy_server_id:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No assets were created or moved."}

    # C1 (15 pts): Parent asset AI-CHASSIS-01 created successfully
    if chassis_01.get("found"):
        score += 15
        feedback.append("C1: AI-CHASSIS-01 created (+15)")
    else:
        feedback.append("C1: AI-CHASSIS-01 not found (+0)")

    # C2 (15 pts): New child assets GPU-H100-101 and GPU-H100-102 created
    gpus_created = 0
    if gpu_101.get("found"): gpus_created += 1
    if gpu_102.get("found"): gpus_created += 1
    
    if gpus_created == 2:
        score += 15
        feedback.append("C2: Both new GPUs (101, 102) created (+15)")
    elif gpus_created == 1:
        score += 7
        feedback.append("C2: Only one new GPU created (+7)")
    else:
        feedback.append("C2: New GPUs not found (+0)")

    # C3 (20 pts): Legacy GPUs GPU-H100-001 & GPU-H100-002 checked in from old chassis
    gpus_checked_in = 0
    if gpu_001.get("found") and str(gpu_001.get("assigned_to", "0")) != legacy_server_id:
        gpus_checked_in += 1
    if gpu_002.get("found") and str(gpu_002.get("assigned_to", "0")) != legacy_server_id:
        gpus_checked_in += 1

    if gpus_checked_in == 2:
        score += 20
        feedback.append("C3: Legacy GPUs (001, 002) successfully checked in/reclaimed (+20)")
    elif gpus_checked_in == 1:
        score += 10
        feedback.append("C3: Only one legacy GPU checked in (+10)")
    else:
        feedback.append("C3: Legacy GPUs still assigned to legacy chassis (+0)")

    # C4 (30 pts): All 4 GPUs checked out to Asset AI-CHASSIS-01
    gpus_assigned = 0
    new_chassis_id = str(chassis_01.get("id", "-1"))
    
    if chassis_01.get("found"):
        for gpu_name, gpu_data in [("101", gpu_101), ("102", gpu_102), ("001", gpu_001), ("002", gpu_002)]:
            if gpu_data.get("found"):
                a_to = str(gpu_data.get("assigned_to", "0"))
                a_type = str(gpu_data.get("assigned_type", ""))
                if a_to == new_chassis_id and "Asset" in a_type:
                    gpus_assigned += 1
                else:
                    feedback.append(f"C4: GPU {gpu_name} not assigned to AI-CHASSIS-01 (Asset) [to={a_to}, type={a_type}]")
            else:
                feedback.append(f"C4: GPU {gpu_name} not found")

        if gpus_assigned == 4:
            score += 30
            feedback.append("C4: All 4 GPUs checked out to AI-CHASSIS-01 as Asset-to-Asset (+30)")
        elif gpus_assigned > 0:
            pts = int(30 * (gpus_assigned / 4))
            score += pts
            feedback.append(f"C4: {gpus_assigned}/4 GPUs correctly checked out to AI-CHASSIS-01 (+{pts})")
        else:
            feedback.append("C4: No GPUs checked out to AI-CHASSIS-01 (+0)")
    else:
        feedback.append("C4: Chassis AI-CHASSIS-01 missing, cannot assign GPUs (+0)")

    # C5 (20 pts): AI-CHASSIS-01 checked out to Location Data Center - Rack 42
    if chassis_01.get("found"):
        a_to = str(chassis_01.get("assigned_to", "0"))
        a_type = str(chassis_01.get("assigned_type", ""))
        rtd_loc = str(chassis_01.get("rtd_location_id", "0"))
        
        if a_to == rack_location_id and "Location" in a_type:
            score += 20
            feedback.append("C5: AI-CHASSIS-01 checked out to Location Data Center - Rack 42 (+20)")
        elif rtd_loc == rack_location_id:
            # Partial credit if they updated default location but didn't actually check it out
            score += 10
            feedback.append("C5: AI-CHASSIS-01 default location set to Rack 42, but not explicitly checked out (+10)")
        else:
            feedback.append("C5: AI-CHASSIS-01 not deployed to correct Location (+0)")
    else:
        feedback.append("C5: AI-CHASSIS-01 not found (+0)")

    passed = score >= 80 and gpus_assigned > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }