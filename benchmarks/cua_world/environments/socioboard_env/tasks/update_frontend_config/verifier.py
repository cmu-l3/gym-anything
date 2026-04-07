#!/usr/bin/env python3
"""
Verifier for update_frontend_config task.

Evaluates:
1. Expected 8 config fields correctly modified in .env (80 points)
2. Critical keys untouched (10 points)
3. Structural integrity (5 points)
4. Anti-gaming file modification timestamp (5 points)
5. VLM trajectory verification to ensure terminal/editor use.
"""

import os
import json
import tempfile
import logging

# Try importing VLM features gracefully
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_env(text):
    """Robustly parses a Laravel/PHP .env file, removing surrounding quotes."""
    env = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '=' in line:
            k, v = line.split('=', 1)
            k = k.strip()
            v = v.strip()
            # Strip quotes if agent wrapped values in them
            if len(v) >= 2 and v.startswith('"') and v.endswith('"'):
                v = v[1:-1]
            elif len(v) >= 2 and v.startswith("'") and v.endswith("'"):
                v = v[1:-1]
            env[k] = v
    return env

def check_duplicates(text):
    """Checks if any configuration keys were duplicated."""
    keys = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'): continue
        if '=' in line:
            keys.append(line.split('=', 1)[0].strip())
    return len(keys) != len(set(keys))

def verify_update_frontend_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {})

    feedback_parts = []
    score = 0

    # Retrieve output and metadata files from container
    files_to_copy = {
        "task_result": "/tmp/task_result.json",
        "final_env": "/tmp/final_env_file.txt",
        "original_env": "/tmp/original_env_values.json",
        "baseline_line_count": "/tmp/baseline_line_count.txt"
    }

    local_files = {}
    for key, remote_path in files_to_copy.items():
        tmp = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                local_files[key] = f.read()
        except Exception as e:
            logger.warning(f"Could not read {remote_path}: {e}")
            local_files[key] = None
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    if not local_files["task_result"] or not local_files["final_env"]:
        return {"passed": False, "score": 0, "feedback": "Failed to read task output files from environment."}

    try:
        result = json.loads(local_files["task_result"])
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Corrupted task result JSON."}

    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": ".env file does not exist. It may have been deleted."}

    # CRITERION 1: 8 Config Values (10 pts each = 80 max)
    env_content = local_files["final_env"]
    parsed_env = parse_env(env_content)
    
    correct_values_count = 0
    for key, expected_val in expected_values.items():
        actual_val = parsed_env.get(key)
        if actual_val == expected_val:
            score += 10
            correct_values_count += 1
        else:
            feedback_parts.append(f"{key} incorrect (Expected '{expected_val}', got '{actual_val}')")

    if correct_values_count == len(expected_values):
        feedback_parts.append("All configuration values are correct.")

    # CRITERION 2: Critical keys integrity (10 pts)
    critical_keys_ok = True
    try:
        orig_vals = json.loads(local_files["original_env"])
        for c_key, c_val in orig_vals.items():
            if parsed_env.get(c_key) != c_val:
                critical_keys_ok = False
                feedback_parts.append(f"CRITICAL: {c_key} was modified or deleted!")
    except Exception:
        feedback_parts.append("Could not verify critical keys.")
        critical_keys_ok = False

    if critical_keys_ok:
        score += 10
        feedback_parts.append("Critical keys intact.")

    # CRITERION 3: Structural integrity (5 pts)
    try:
        baseline_count = int(local_files["baseline_line_count"].strip())
        current_count = result.get("env_line_count", 0)
        has_duplicates = check_duplicates(env_content)

        if abs(current_count - baseline_count) <= 5 and not has_duplicates:
            score += 5
            feedback_parts.append("Structural integrity ok.")
        else:
            feedback_parts.append(f"Structural integrity compromised (Line count diff: {abs(current_count - baseline_count)}, Duplicates: {has_duplicates}).")
    except Exception:
        feedback_parts.append("Could not verify structural integrity.")

    # CRITERION 4: Anti-gaming (Modification timestamp) (5 pts)
    mtime = result.get("env_mtime", 0)
    start_time = result.get("task_start_time", 0)
    if mtime > start_time:
        score += 5
        feedback_parts.append("File modification timestamp valid.")
    else:
        feedback_parts.append("File modification timestamp indicates no changes were saved after task start.")

    # CRITERION 5: Trajectory Verification (VLM Check)
    vlm_passed = True
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames

            prompt = (
                "Look at these screenshots from a user's desktop session. "
                "Did the user open a terminal, text editor, or file manager to edit a configuration file? "
                "Respond ONLY with a JSON object: {\"terminal_used\": true} or {\"terminal_used\": false}"
            )
            vlm_res = query_vlm(images=images, prompt=prompt)
            
            if vlm_res and "parsed" in vlm_res:
                vlm_passed = vlm_res["parsed"].get("terminal_used", True)
            elif vlm_res and vlm_res.get("response"):
                vlm_passed = "true" in vlm_res["response"].lower()

            if not vlm_passed:
                feedback_parts.append("VLM Check: No terminal or text editor usage detected in trajectory.")
                score = min(score, 50)  # Heavy penalty for gaming without doing work
        except Exception as e:
            logger.warning(f"VLM verification failed to run: {e}")

    # Final pass conditions:
    # Requires a passing grade, at least 6/8 settings right, unmodified critical keys, and valid trajectory
    passed = (score >= 60 and correct_values_count >= 6 and critical_keys_ok and vlm_passed)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }