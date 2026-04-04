#!/usr/bin/env python3
"""
Verifier for configure_global_env_vars task.
Checks global environment variables configuration and verification job build output.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_global_env_vars(traj, env_info, task_info):
    """
    Verify the configure_global_env_vars task.
    
    Returns:
        dict with 'passed', 'score' (0-100) and 'feedback' string
    """
    # 1. Setup - Get data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_vars = metadata.get('expected_vars', {
        "DEPLOY_TARGET": "staging-cluster-01",
        "API_BASE_URL": "https://api.example.com/v2",
        "BUILD_RETENTION_DAYS": "30"
    })
    job_name = metadata.get('job_name', "EnvVar-Verification-Job")
    
    score = 0
    feedback_parts = []
    
    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_global_env_vars_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Failed to load verification data: {e}. The export script may not have run correctly."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    # ============================================================
    # CRITERION 1: Global env vars exist in system config (15 points)
    # ============================================================
    global_vars = result_data.get("global_env_vars", {})
    num_expected_found = 0
    
    # We check if *any* of our expected keys exist
    found_keys = []
    for key in expected_vars:
        if key in global_vars:
            num_expected_found += 1
            found_keys.append(key)
    
    if num_expected_found >= 3:
        score += 15
        feedback_parts.append(f"[+15] All 3 global environment variables found in Jenkins config.")
    elif num_expected_found > 0:
        partial = int(15 * num_expected_found / 3)
        score += partial
        feedback_parts.append(f"[+{partial}] {num_expected_found}/3 global environment variables found ({', '.join(found_keys)}).")
    else:
        feedback_parts.append(f"[+0] No relevant global environment variables configured.")
    
    # ============================================================
    # CRITERION 2, 3, 4: Specific Variable Values (10 points each)
    # ============================================================
    for key, expected_val in expected_vars.items():
        actual_val = global_vars.get(key, "")
        if actual_val == expected_val:
            score += 10
            feedback_parts.append(f"[+10] {key} correctly set to '{actual_val}'.")
        elif actual_val:
            feedback_parts.append(f"[+0] {key} has wrong value: '{actual_val}' (expected '{expected_val}').")
        else:
            feedback_parts.append(f"[+0] {key} not found.")
    
    # ============================================================
    # CRITERION 5: Job exists (10 points)
    # ============================================================
    job_info = result_data.get("job", {})
    job_exists = job_info.get("exists", False)
    
    if job_exists:
        score += 10
        feedback_parts.append(f"[+10] Job '{job_name}' exists.")
    else:
        feedback_parts.append(f"[+0] Job '{job_name}' not found.")
    
    # ============================================================
    # CRITERION 6: Job is Freestyle (5 points)
    # ============================================================
    job_class = job_info.get("class", "none")
    if "FreeStyleProject" in job_class or "freeStyleProject" in job_class:
        score += 5
        feedback_parts.append(f"[+5] Job is a Freestyle project.")
    elif job_exists:
        # Give small partial credit if it's any kind of job
        score += 2
        feedback_parts.append(f"[+2] Job exists but is not a Freestyle project (class: {job_class}).")
    else:
        feedback_parts.append(f"[+0] Cannot check job type.")
    
    # ============================================================
    # CRITERION 7: Build was triggered (10 points)
    # ============================================================
    build_info = result_data.get("build", {})
    build_number = build_info.get("number", 0)
    
    if build_number > 0:
        score += 10
        feedback_parts.append(f"[+10] Build #{build_number} was triggered.")
    else:
        feedback_parts.append(f"[+0] No build found for the job.")
    
    # ============================================================
    # CRITERION 8: Build succeeded (10 points)
    # ============================================================
    build_result = build_info.get("result", "NONE")
    build_building = build_info.get("building", False)
    
    if build_result == "SUCCESS":
        score += 10
        feedback_parts.append(f"[+10] Build completed successfully.")
    elif build_building:
        score += 3
        feedback_parts.append(f"[+3] Build is still running.")
    elif build_result in ("FAILURE", "UNSTABLE", "ABORTED"):
        score += 2
        feedback_parts.append(f"[+2] Build completed but with result: {build_result}.")
    else:
        feedback_parts.append(f"[+0] Build result: {build_result}.")
    
    # ============================================================
    # CRITERION 9, 10, 11: Console Output matches values (20 points total)
    # ============================================================
    # This verifies the variables actually propagated to the build runtime
    console = result_data.get("console_output", "")
    
    # DEPLOY_TARGET (7 points)
    tgt_key = "DEPLOY_TARGET"
    tgt_exp = expected_vars[tgt_key]
    if f"{tgt_key}={tgt_exp}" in console:
        score += 7
        feedback_parts.append(f"[+7] Console output confirms {tgt_key} is correct.")
    elif f"{tgt_key}=" in console:
        score += 2
        feedback_parts.append(f"[+2] Console mentions {tgt_key} but value mismatch.")
    else:
        feedback_parts.append(f"[+0] {tgt_key} verification failed in console log.")
        
    # API_BASE_URL (7 points)
    api_key = "API_BASE_URL"
    api_exp = expected_vars[api_key]
    if f"{api_key}={api_exp}" in console:
        score += 7
        feedback_parts.append(f"[+7] Console output confirms {api_key} is correct.")
    elif f"{api_key}=" in console:
        score += 2
        feedback_parts.append(f"[+2] Console mentions {api_key} but value mismatch.")
    else:
        feedback_parts.append(f"[+0] {api_key} verification failed in console log.")

    # BUILD_RETENTION_DAYS (6 points)
    ret_key = "BUILD_RETENTION_DAYS"
    ret_exp = expected_vars[ret_key]
    if f"{ret_key}={ret_exp}" in console:
        score += 6
        feedback_parts.append(f"[+6] Console output confirms {ret_key} is correct.")
    elif f"{ret_key}=" in console:
        score += 2
        feedback_parts.append(f"[+2] Console mentions {ret_key} but value mismatch.")
    else:
        feedback_parts.append(f"[+0] {ret_key} verification failed in console log.")

    # ============================================================
    # Anti-gaming: Check build happened after task start
    # ============================================================
    task_start = result_data.get("task_start_time", 0)
    build_timestamp_ms = build_info.get("timestamp", 0)
    build_timestamp_s = build_timestamp_ms / 1000 if build_timestamp_ms > 0 else 0
    
    if task_start > 0 and build_timestamp_s > 0:
        if build_timestamp_s < task_start:
            # Build happened before task started — suspicious
            score = max(0, score - 50)
            feedback_parts.append(f"[-50] PENALTY: Build detected before task start time. Possible gaming.")

    # Final logic
    passed = score >= 60
    
    # Require at least one global var configured AND the job exists to pass
    # (Prevents passing with just one or the other if points were tweaked)
    critical_success = (num_expected_found >= 1) and job_exists and (build_number > 0)
    if not critical_success and passed:
        passed = False
        feedback_parts.append("FAIL: Critical criteria missing (Env vars + Job + Build required).")

    return {
        "passed": passed,
        "score": float(score),
        "feedback": "\n".join(feedback_parts)
    }