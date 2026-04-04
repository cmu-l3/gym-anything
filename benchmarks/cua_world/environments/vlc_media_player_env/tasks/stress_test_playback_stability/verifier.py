#!/usr/bin/env python3
"""
Verifier for Stress Test Playback Stability task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_stress_test_playback_stability(traj, env_info, task_info):
    """
    Verify stress test playback stability task completion.
    
    Checks:
    1. Stability log exists and has content
    2. No crash indicators found in log
    3. Result report created (either by user or by export script)
    
    This verifies that:
    - VLC was launched and logged activity
    - No crashes or fatal errors occurred during playback
    - Task completed successfully
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Criterion 1: Verify stability log exists and has content
    temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/vlc_stability_log.txt", temp_log.name)
        
        # Check log has content
        log_size = os.path.getsize(temp_log.name)
        
        if log_size > 100:  # At least 100 bytes of log content
            criteria_met += 1
            
            # Count lines for feedback
            with open(temp_log.name, 'r', errors='ignore') as f:
                log_lines = len(f.readlines())
            
            feedback_parts.append(f"✅ Stability log captured ({log_lines} lines, {log_size} bytes)")
        else:
            feedback_parts.append(f"⚠️ Stability log too small ({log_size} bytes)")
        
        os.unlink(temp_log.name)
        
    except Exception as e:
        logger.error(f"Error reading stability log: {e}", exc_info=True)
        feedback_parts.append(f"❌ Stability log not found or unreadable")
    
    # Criterion 2: Check for crash indicators in log
    temp_log2 = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/vlc_stability_log.txt", temp_log2.name)
        
        with open(temp_log2.name, 'r', errors='ignore') as f:
            log_content = f.read().lower()
        
        # Check for various crash/error indicators
        crash_indicators = [
            "segmentation fault",
            "core dumped", 
            "fatal error",
            "crashed",
            "signal 11",  # SIGSEGV
            "signal 6",   # SIGABRT
        ]
        
        found_indicators = [ind for ind in crash_indicators if ind in log_content]
        
        if not found_indicators:
            criteria_met += 1
            feedback_parts.append("✅ No crash indicators in log")
        else:
            feedback_parts.append(f"❌ Found crash indicators: {', '.join(found_indicators)}")
        
        os.unlink(temp_log2.name)
        
    except Exception as e:
        logger.error(f"Error checking crash indicators: {e}", exc_info=True)
        feedback_parts.append("⚠️ Could not check for crash indicators")
    
    # Criterion 3: Check result report or JSON metadata
    result_found = False
    
    # First try to get user-created result report
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/Videos/stress_test_result.txt", temp_result.name)
        
        with open(temp_result.name, 'r', errors='ignore') as f:
            result_content = f.read().lower()
        
        # Check for success indicators
        success_words = ["success", "passed", "stable", "complete", "ok"]
        if len(result_content) > 10 and any(word in result_content for word in success_words):
            result_found = True
            feedback_parts.append("✅ User created result report confirms success")
        
        os.unlink(temp_result.name)
        
    except Exception:
        pass  # User report might not exist, check JSON instead
    
    # If no user report, check JSON metadata from export script
    if not result_found:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/vlc_stability_result.json", temp_json.name)
            
            with open(temp_json.name, 'r') as f:
                result_data = json.load(f)
            
            crash_count = result_data.get('crash_indicators_found', 999)
            vlc_was_running = result_data.get('vlc_running_at_export', False)
            log_size = result_data.get('log_size_lines', 0)
            
            # If VLC was running and no crashes, consider it successful
            if crash_count == 0 and log_size > 5:
                result_found = True
                feedback_parts.append(f"✅ Export metadata confirms stability (VLC running: {vlc_was_running})")
            else:
                feedback_parts.append(f"⚠️ Export metadata shows issues (crashes: {crash_count})")
            
            os.unlink(temp_json.name)
            
        except Exception as e:
            logger.error(f"Error reading result JSON: {e}", exc_info=True)
            feedback_parts.append("⚠️ No result report or metadata found")
    
    if result_found:
        criteria_met += 1
    
    # Check completion marker (optional, for additional context)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_stress_test_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r', errors='ignore') as f:
            marker_content = f.read()
        
        # Extract info from marker
        if "completed" in marker_content.lower():
            feedback_parts.append("✅ Task completed")
        
        os.unlink(temp_marker.name)
        
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }