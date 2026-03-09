#!/usr/bin/env python3
"""
Verifier for Auto Stop Sleep Timer task (auto_stop_sleep_timer@1)

Checks that VLC was configured to automatically terminate after the specified runtime.
"""

import sys
import os
import logging
import tempfile
import json
import subprocess
import time

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_vlc_running_in_container(env_info) -> bool:
    """Check if VLC process is currently running in the container."""
    try:
        # Try to execute pgrep in container
        exec_in_env = env_info.get('exec_in_env')
        if exec_in_env:
            result = exec_in_env('pgrep -f vlc', user='ga')
            return result.returncode == 0
    except Exception as e:
        logger.debug(f"Could not check VLC process in container: {e}")
    
    return False


def wait_for_vlc_termination(env_info, max_wait_sec: int = 60, poll_interval: int = 2) -> tuple:
    """
    Wait for VLC to terminate in the container, up to max_wait_sec.
    
    Returns:
        (terminated, elapsed_time, was_running_initially)
    """
    start_time = time.time()
    was_running = check_vlc_running_in_container(env_info)
    
    if not was_running:
        logger.info("VLC not running initially")
        return True, 0, False
    
    logger.info(f"VLC running, waiting up to {max_wait_sec}s for termination...")
    
    while time.time() - start_time < max_wait_sec:
        if not check_vlc_running_in_container(env_info):
            elapsed = time.time() - start_time
            logger.info(f"VLC terminated after {elapsed:.1f} seconds")
            return True, elapsed, True
        
        time.sleep(poll_interval)
    
    elapsed = time.time() - start_time
    logger.warning(f"VLC still running after {elapsed:.1f} seconds")
    return False, elapsed, True


def verify_sleep_timer(traj, env_info, task_info):
    """
    Verify that VLC was configured to automatically stop after target runtime.
    
    Args:
        traj: Trajectory data
        env_info: Environment information with copy_from_env function
        task_info: Task metadata with target_runtime_sec and tolerance_sec
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get task parameters
    metadata = task_info.get('metadata', {})
    target_runtime = metadata.get('target_runtime_sec', 45)
    tolerance = metadata.get('tolerance_sec', 10)
    
    logger.info(f"Verifying VLC sleep timer (target: {target_runtime}s, tolerance: ±{tolerance}s)")
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_sleep_timer_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        start_timestamp = int(result.get('start_timestamp', 0))
        end_timestamp = int(result.get('end_timestamp', 0))
        vlc_still_running = result.get('vlc_still_running', False)
        launch_cmd = result.get('launch_command', '')
        
        logger.info(f"Result: start={start_timestamp}, end={end_timestamp}, running={vlc_still_running}")
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Error reading result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}
    
    # Criterion 1: VLC was started (has start timestamp)
    if start_timestamp > 0:
        criteria_met += 1
        feedback_parts.append("✅ VLC launched successfully")
    else:
        feedback_parts.append("❌ VLC was not started (no start timestamp)")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
    
    # Criterion 2: Check if correct configuration was used (runtime flag or timeout command)
    config_correct = False
    if launch_cmd:
        if '--run-time' in launch_cmd or 'timeout' in launch_cmd:
            criteria_met += 1
            config_correct = True
            feedback_parts.append(f"✅ Correct runtime configuration detected: {launch_cmd[:50]}...")
        else:
            feedback_parts.append(f"⚠️ Launch command found but no runtime parameter: {launch_cmd[:50]}...")
    else:
        feedback_parts.append("⚠️ Launch command not recorded")
    
    # Criterion 3: VLC terminated (not running at export time)
    if not vlc_still_running:
        criteria_met += 1
        feedback_parts.append("✅ VLC terminated successfully")
    else:
        feedback_parts.append("❌ VLC still running at export (did not auto-terminate)")
        # If still running, it's a failure
        score = int((criteria_met / total_criteria) * 100)
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    # Criterion 4: Runtime within acceptable range
    if end_timestamp > start_timestamp:
        actual_runtime = end_timestamp - start_timestamp
        
        logger.info(f"Actual VLC runtime: {actual_runtime}s (target: {target_runtime}s)")
        
        min_runtime = target_runtime - tolerance
        max_runtime = target_runtime + tolerance
        
        if min_runtime <= actual_runtime <= max_runtime:
            criteria_met += 1
            deviation = abs(actual_runtime - target_runtime)
            feedback_parts.append(
                f"✅ Runtime within tolerance: {actual_runtime}s "
                f"(target: {target_runtime}s, deviation: {deviation}s)"
            )
        elif actual_runtime < min_runtime:
            feedback_parts.append(
                f"⚠️ Terminated too early: {actual_runtime}s < {min_runtime}s "
                f"(may have crashed or been killed prematurely)"
            )
        else:
            feedback_parts.append(
                f"⚠️ Terminated too late: {actual_runtime}s > {max_runtime}s "
                f"(timer may not have been configured correctly)"
            )
    else:
        feedback_parts.append("⚠️ Could not calculate runtime (invalid timestamps)")
    
    # Check for zombie processes
    try:
        exec_in_env = env_info.get('exec_in_env')
        if exec_in_env:
            result = exec_in_env('pgrep -f vlc', user='ga')
            if result.returncode == 0:
                feedback_parts.append("⚠️ Warning: VLC process still detected (possible zombie)")
    except Exception:
        pass
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_sleep_timer_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            content = f.read()
        logger.info(f"Completion marker content: {content[:100]}")
        os.unlink(temp_marker.name)
    except Exception as e:
        logger.warning(f"Completion marker not found: {e}")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Calculate accuracy bonus for near-perfect timing
    if criteria_met == total_criteria and end_timestamp > start_timestamp:
        actual_runtime = end_timestamp - start_timestamp
        deviation = abs(actual_runtime - target_runtime)
        accuracy = 1.0 - (deviation / tolerance) if tolerance > 0 else 1.0
        accuracy = max(0.0, min(1.0, accuracy))
        
        # Boost score slightly for accurate timing
        if accuracy > 0.7:
            score = min(100, score + int(accuracy * 5))
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
