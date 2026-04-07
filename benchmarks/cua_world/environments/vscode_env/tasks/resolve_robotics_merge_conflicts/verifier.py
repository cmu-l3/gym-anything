#!/usr/bin/env python3
"""
Verifier for Resolve Robotics Merge Conflicts task.

Checks whether the agent resolved merge conflicts in 5 files,
preserving functionality from both branches, avoiding syntax errors,
and successfully committing the merge.
"""

import sys
import os
import json
import ast
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def has_conflict_markers(content: str) -> bool:
    """Check if standard git conflict markers are still present."""
    markers = ['<<<<<<<', '=======', '>>>>>>>']
    return any(marker in content for marker in markers)

def parses_as_python(content: str) -> bool:
    """Check if the string is valid Python syntax."""
    if not content.strip():
        return False
    try:
        ast.parse(content)
        return True
    except SyntaxError:
        return False

def verify_merge_conflicts(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/merge_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    files = result.get("files", {})
    git_status = result.get("git_status", "")
    git_log = result.get("git_log", "")
    task_start_time = result.get("task_start_time", 0)

    score = 0
    feedback = []

    # 1. Check config/robot_params.yaml (15 points)
    yaml_src = files.get("config/robot_params.yaml", "")
    if has_conflict_markers(yaml_src):
        feedback.append("[-] robot_params.yaml: Still contains conflict markers (0/15)")
    else:
        has_imu = "imu:" in yaml_src and "BNO055" in yaml_src
        has_motors = "motors:" in yaml_src and "pid:" in yaml_src
        if has_imu and has_motors:
            score += 15
            feedback.append("[+] robot_params.yaml: Successfully merged both sensor and motor configs (15/15)")
        elif has_imu or has_motors:
            score += 5
            feedback.append("[~] robot_params.yaml: Partially resolved, missing either IMU or PID configs (5/15)")
        else:
            feedback.append("[-] robot_params.yaml: Missing required configurations (0/15)")

    # 2. Check src/robot_controller.py (20 points)
    ctrl_src = files.get("src/robot_controller.py", "")
    if has_conflict_markers(ctrl_src):
        feedback.append("[-] robot_controller.py: Still contains conflict markers (0/20)")
    elif not parses_as_python(ctrl_src):
        feedback.append("[-] robot_controller.py: Contains Python syntax errors (0/20)")
    else:
        has_imu_init = "self.imu" in ctrl_src
        has_pid_init = "self.pid" in ctrl_src
        has_sensor_read = "fuse_orientation" in ctrl_src
        has_dt_calc = "self.dt =" in ctrl_src or "self.dt=" in ctrl_src
        
        matches = sum([has_imu_init, has_pid_init, has_sensor_read, has_dt_calc])
        if matches == 4:
            score += 20
            feedback.append("[+] robot_controller.py: Cleanly merged initializations and methods (20/20)")
        elif matches > 0:
            subscore = matches * 4
            score += subscore
            feedback.append(f"[~] robot_controller.py: Partially resolved logic ({subscore}/20)")
        else:
            feedback.append("[-] robot_controller.py: Critical logic from branches is missing (0/20)")

    # 3. Check src/utils/transforms.py (15 points)
    trans_src = files.get("src/utils/transforms.py", "")
    if has_conflict_markers(trans_src):
        feedback.append("[-] transforms.py: Still contains conflict markers (0/15)")
    elif not parses_as_python(trans_src):
        feedback.append("[-] transforms.py: Contains Python syntax errors (0/15)")
    else:
        has_quat = "def quaternion_to_euler" in trans_src
        has_clamp = "def clamp_value" in trans_src
        has_avg = "def moving_average" in trans_src
        has_numpy = "import numpy" in trans_src
        has_deque = "from collections import deque" in trans_src
        
        if has_quat and has_clamp and has_avg and has_numpy and has_deque:
            score += 15
            feedback.append("[+] transforms.py: All imports and math functions preserved (15/15)")
        elif has_quat or has_clamp or has_avg:
            score += 5
            feedback.append("[~] transforms.py: Partially preserved functions (5/15)")
        else:
            feedback.append("[-] transforms.py: Missing added functions (0/15)")

    # 4. Check tests/test_controller.py (15 points)
    test_src = files.get("tests/test_controller.py", "")
    if has_conflict_markers(test_src):
        feedback.append("[-] test_controller.py: Still contains conflict markers (0/15)")
    elif not parses_as_python(test_src):
        feedback.append("[-] test_controller.py: Contains Python syntax errors (0/15)")
    else:
        has_imu_test = "def test_imu_data_integration" in test_src
        has_pid_test = "def test_pid_response_convergence" in test_src
        mock_imu = "mock_imu" in test_src
        mock_pid = "mock_pid" in test_src
        
        if has_imu_test and has_pid_test and mock_imu and mock_pid:
            score += 15
            feedback.append("[+] test_controller.py: Test fixtures and methods merged successfully (15/15)")
        elif has_imu_test or has_pid_test:
            score += 5
            feedback.append("[~] test_controller.py: Partially merged tests (5/15)")
        else:
            feedback.append("[-] test_controller.py: Tests from feature branches missing (0/15)")

    # 5. Check README.md (10 points)
    readme_src = files.get("README.md", "")
    if has_conflict_markers(readme_src):
        feedback.append("[-] README.md: Still contains conflict markers (0/10)")
    else:
        has_imu_feature = "IMU Sensor Fusion" in readme_src
        has_pid_feature = "Adaptive PID Control" in readme_src
        has_imu_docs = "Sensor Configuration" in readme_src
        has_pid_docs = "PID Tuning Guide" in readme_src
        
        if has_imu_feature and has_pid_feature and has_imu_docs and has_pid_docs:
            score += 10
            feedback.append("[+] README.md: Both feature documentations preserved (10/10)")
        elif has_imu_feature or has_pid_feature:
            score += 5
            feedback.append("[~] README.md: Partially merged documentation (5/10)")
        else:
            feedback.append("[-] README.md: Missing documentation updates (0/10)")

    # 6. Check Git State (15 points)
    # git_log format: "%H|%P|%s|%at" -> Hash | Parents | Subject | Timestamp
    parts = git_log.split('|')
    is_merge_commit = False
    commit_after_start = False
    
    if len(parts) >= 4:
        parents = parts[1].split()
        timestamp = int(parts[3]) if parts[3].isdigit() else 0
        
        if len(parents) >= 2:
            is_merge_commit = True
        if timestamp > task_start_time:
            commit_after_start = True

    is_clean = (git_status.strip() == "")

    if is_clean and is_merge_commit and commit_after_start:
        score += 15
        feedback.append("[+] Git: Merge successfully committed and working tree clean (15/15)")
    elif is_clean and commit_after_start:
        score += 5
        feedback.append("[~] Git: Working tree clean, but recent commit is not a merge commit (5/15)")
    else:
        feedback.append("[-] Git: Working tree is dirty or merge not committed (0/15)")

    # 7. VLM Verification (10 points) - Verify VS Code was used to resolve
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            vlm_prompt = (
                "Look at these screenshots of a VS Code environment. "
                "Did the user interact with the code editor or source control panel "
                "to resolve merge conflicts? Reply YES if there is evidence of code editing or git interaction."
            )
            try:
                vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
                if vlm_result and "yes" in str(vlm_result.get("response", "")).lower():
                    score += 10
                    feedback.append("[+] VLM: Visual evidence of merge conflict resolution workflow (10/10)")
                else:
                    feedback.append("[-] VLM: Could not verify visual workflow of resolving conflicts (0/10)")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                feedback.append(f"[-] VLM: Check failed ({e})")
        else:
            feedback.append("[-] VLM: No frames available for verification (0/10)")
    else:
        # Give free points if VLM not configured but textual tests pass highly
        if score >= 70:
            score += 10
            feedback.append("[+] VLM: Automatically awarded (VLM not available but text passed highly)")

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }