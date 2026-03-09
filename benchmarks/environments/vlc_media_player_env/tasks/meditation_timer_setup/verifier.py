#!/usr/bin/env python3
"""
Verifier for Meditation Timer Setup task
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


def verify_meditation_timer_setup(traj, env_info, task_info):
    """
    Verify meditation timer setup task completion.
    
    Checks:
    1. Video file exists (task setup worked)
    2. Timer configured (found in history or config)
    3. Practical test passed (timer actually works)
    
    Returns:
        dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        try:
            copy_from_env("/tmp/vlc_meditation_timer_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying timer result: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Error copying timer result: {str(e)}"}
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        # Extract results
        timer_configured = result.get('timer_configured', False)
        timer_value = result.get('timer_value', '')
        timer_source = result.get('timer_source', 'none')
        config_method = result.get('config_method', '')
        practical_test_passed = result.get('practical_test_passed', False)
        test_output = result.get('test_output', '')
        video_path = result.get('video_path', '')
        
        # Criterion 1: Video file exists
        if video_path and 'nature_meditation.mp4' in video_path:
            criteria_met += 0.5
            feedback_parts.append("✅ Meditation video present")
        else:
            feedback_parts.append("⚠️ Meditation video not found")
        
        # Criterion 2: Timer configured (main criterion - double weight)
        if timer_configured and timer_value == "1800":
            criteria_met += 1.5
            feedback_parts.append(f"✅ Timer configured: {timer_value}s via {config_method} [{timer_source}]")
        elif timer_configured:
            criteria_met += 0.75
            feedback_parts.append(f"⚠️ Timer configured but wrong value: {timer_value}s (expected 1800s)")
        else:
            feedback_parts.append("❌ Timer not configured (no --run-time=1800 found)")
        
        # Criterion 3: Practical test passed
        if practical_test_passed:
            criteria_met += 1.0
            feedback_parts.append(f"✅ Practical test: {test_output}")
        else:
            feedback_parts.append(f"❌ Practical test failed: {test_output}")
        
        os.unlink(temp_result.name)
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Invalid result format: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading timer result: {str(e)}"}
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_meditation_timer_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score (out of 3.0 total criteria points)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
