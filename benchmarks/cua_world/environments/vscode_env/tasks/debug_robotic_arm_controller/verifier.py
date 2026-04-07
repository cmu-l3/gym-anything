#!/usr/bin/env python3
"""
Verifier for debug_robotic_arm_controller task.

Checks whether the agent fixed 5 critical bugs in a robotic arm simulator.
Validates both through pytest execution results and static code analysis
to prevent gaming (e.g., hardcoding test assertions).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_robotic_arm_controller(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback_parts = []
    
    test_log = result.get("pytest_log", "")

    # 1. PID Derivative Kick
    pid_data = result.get("controller/pid.py", {})
    pid_src = pid_data.get("content", "")
    pid_modified = pid_data.get("modified", False)
    
    if "test_pid.py::test_no_derivative_kick PASSED" in test_log:
        score += 15
        feedback_parts.append("PID test passed (15/15)")
        # Code pattern check: derivative must use PV instead of error
        if re.search(r'derivative\s*=\s*[-]?\s*\(?\s*pv\s*-\s*self\.prev_pv', pid_src) or ("error" not in re.findall(r'derivative\s*=\s*(.*)', pid_src)[0]):
            score += 5
            feedback_parts.append("PID code pattern correct (5/5)")
        else:
            feedback_parts.append("PID code pattern incorrect (0/5)")
    else:
        feedback_parts.append("PID test failed (0/20)")

    # 2. Filter Coefficients
    filter_data = result.get("sensors/filter.py", {})
    filter_src = filter_data.get("content", "")
    
    if "test_filter.py::test_noise_attenuation PASSED" in test_log:
        score += 15
        feedback_parts.append("Filter test passed (15/15)")
        if re.search(r'self\.alpha\s*\*\s*raw_value', filter_src) and re.search(r'\(1\s*-\s*self\.alpha\)\s*\*\s*self\.value', filter_src):
            score += 5
            feedback_parts.append("Filter code pattern correct (5/5)")
        else:
            feedback_parts.append("Filter code pattern incorrect (0/5)")
    else:
        feedback_parts.append("Filter test failed (0/20)")

    # 3. Kinematics Atan2 Order
    ik_data = result.get("kinematics/inverse.py", {})
    ik_src = ik_data.get("content", "")
    
    if "test_kinematics.py::test_known_positions PASSED" in test_log:
        score += 15
        feedback_parts.append("IK test passed (15/15)")
        if re.search(r'math\.atan2\(\s*y\s*,\s*x\s*\)', ik_src):
            score += 5
            feedback_parts.append("IK code pattern correct (5/5)")
        else:
            feedback_parts.append("IK code pattern incorrect (0/5)")
    else:
        feedback_parts.append("IK test failed (0/20)")

    # 4. Trajectory Planner Overshoot
    traj_data = result.get("controller/trajectory_planner.py", {})
    traj_src = traj_data.get("content", "")
    
    if "test_trajectory.py::test_endpoint_accuracy PASSED" in test_log:
        score += 10
        feedback_parts.append("Trajectory test passed (10/10)")
        if re.search(r'2\.0\s*\*\s*self\.amax', traj_src) or re.search(r'/\s*\(\s*2\s*\*\s*self\.amax\s*\)', traj_src):
            score += 5
            feedback_parts.append("Trajectory code pattern correct (5/5)")
            # Bonus 5 pts for test passing (allocated dynamically to match 20 total)
            score += 5
        else:
            feedback_parts.append("Trajectory code pattern incorrect (0/10)")
    else:
        feedback_parts.append("Trajectory test failed (0/20)")

    # 5. Safety Pre-check
    safety_data = result.get("safety/limits.py", {})
    safety_src = safety_data.get("content", "")
    
    if "test_safety.py::test_velocity_precheck PASSED" in test_log:
        score += 10
        feedback_parts.append("Safety test passed (10/10)")
        
        # Check if commanded_vel assignment happens BEFORE position update
        vel_idx = safety_src.find("commanded_vel =")
        pos_idx = safety_src.find("new_pos =")
        exp_pos_idx = safety_src.find("expected_pos =")
        
        if (vel_idx != -1 and pos_idx != -1 and vel_idx < pos_idx) or (vel_idx != -1 and exp_pos_idx != -1 and vel_idx < exp_pos_idx):
            score += 5
            feedback_parts.append("Safety code pattern correct (5/5)")
            score += 5
        else:
            feedback_parts.append("Safety code pattern incorrect (0/10)")
    else:
        feedback_parts.append("Safety test failed (0/20)")

    # Ensure anti-gaming
    total_modified = sum(1 for d in [pid_data, filter_data, ik_data, traj_data, safety_data] if d.get("modified", False))
    if total_modified == 0 and score > 0:
        score = 0
        feedback_parts = ["FAILED: No files were modified after task start time (Gaming detected)"]

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }