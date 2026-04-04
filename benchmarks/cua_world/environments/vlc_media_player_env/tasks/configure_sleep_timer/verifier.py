#!/usr/bin/env python3
"""
Verifier for Configure Sleep Timer task

This verifier checks if VLC was correctly configured to play for 45 minutes
and then automatically quit, without actually waiting 45 minutes.
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_runtime_configuration(content: str) -> tuple:
    """
    Check if VLC was configured with runtime parameters.
    
    Args:
        content: Text content to search (process info, command history, etc.)
        
    Returns:
        Tuple of (runtime_configured, duration_seconds, method_used)
    """
    # Look for --run-time or --stop-time flags
    runtime_match = re.search(r'--run-time[=\s]+(\d+)', content)
    stoptime_match = re.search(r'--stop-time[=\s]+(\d+)', content)
    
    if runtime_match:
        duration = int(runtime_match.group(1))
        return True, duration, "run-time"
    elif stoptime_match:
        duration = int(stoptime_match.group(1))
        return True, duration, "stop-time"
    
    return False, 0, "none"


def verify_configure_sleep_timer(traj, env_info, task_info):
    """
    Verify the sleep timer configuration task.
    
    We verify:
    1. VLC was launched with the correct video file
    2. VLC was configured with --run-time or --stop-time parameter
    3. Duration is set to 45 minutes (2700 seconds) with reasonable tolerance
    4. (Optional) VLC was configured to quit with --play-and-exit
    
    Args:
        traj: Trajectory information
        env_info: Environment information (contains copy_from_env function)
        task_info: Task information
        
    Returns:
        Verification result dictionary with score, feedback, and passed status
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    criteria_met = 0
    max_score = 100.0
    score = 0.0
    feedback_parts = []
    
    # Try to copy the main result JSON first
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = None
    
    try:
        copy_from_env("/tmp/vlc_sleep_timer_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_result.name)
        logger.info("Successfully loaded result JSON")
    except Exception as e:
        logger.warning(f"Could not load result JSON: {e}")
        result_data = None
    
    # Extract file contents for manual parsing if JSON not available
    all_content = ""
    
    for file_path in ['/tmp/vlc_process_info.txt', '/tmp/vlc_command_history.txt', '/tmp/bash_vlc_history.txt']:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(file_path, temp_file.name)
            with open(temp_file.name, 'r') as f:
                content = f.read()
                all_content += content + "\n"
            os.unlink(temp_file.name)
        except Exception as e:
            logger.warning(f"Could not copy {file_path}: {e}")
    
    # Criterion 1: Verify correct video file was used (20 points)
    video_file_correct = False
    
    if result_data and result_data.get('video_file_found'):
        video_file_correct = True
    elif 'relaxing_thunderstorm.mp4' in all_content or 'relaxing_thunderstorm' in all_content:
        video_file_correct = True
    
    if video_file_correct:
        feedback_parts.append("✅ Correct video file (relaxing_thunderstorm.mp4) was used")
        score += 20
    else:
        feedback_parts.append("✗ Could not verify correct video file was used")
        feedback_parts.append("  Expected: relaxing_thunderstorm.mp4")
    
    # Criterion 2: Verify runtime parameter was configured (30 points)
    runtime_configured = False
    duration = 0
    method = "none"
    
    if result_data and result_data.get('runtime_captured'):
        runtime_configured = True
        duration = result_data.get('runtime_value', 0)
        method = "detected"
    else:
        # Try manual parsing
        runtime_configured, duration, method = check_runtime_configuration(all_content)
    
    if runtime_configured:
        feedback_parts.append(f"✅ VLC configured with runtime parameter: {duration}s")
        score += 30
    else:
        feedback_parts.append("✗ No runtime parameter (--run-time or --stop-time) found")
        feedback_parts.append("  VLC needs --run-time=2700 to quit after 45 minutes")
    
    # Criterion 3: Verify duration is correct - 45 minutes = 2700 seconds (30 points)
    # Accept tolerance: 2400-3000 seconds (40-50 minutes)
    correct_duration = False
    
    if runtime_configured:
        tolerance_min = result_data.get('tolerance_min', 2400) if result_data else 2400
        tolerance_max = result_data.get('tolerance_max', 3000) if result_data else 3000
        
        if tolerance_min <= duration <= tolerance_max:
            correct_duration = True
            minutes = duration / 60
            feedback_parts.append(f"✅ Duration correctly set to {duration} seconds ({minutes:.1f} minutes)")
            score += 30
        elif 60 <= duration < tolerance_min:
            # Agent tested with shorter duration - partial credit
            minutes = duration / 60
            feedback_parts.append(f"⚠️ Duration set to {duration}s ({minutes:.1f} min) - acceptable for testing")
            feedback_parts.append(f"  Expected final config: ~2700 seconds (45 minutes)")
            score += 15  # Partial credit for having a timer
        elif duration < 60:
            # Very short duration - minimal credit
            feedback_parts.append(f"⚠️ Duration very short: {duration}s - may be testing only")
            feedback_parts.append(f"  Expected: ~2700 seconds (45 minutes)")
            score += 5
        else:
            # Duration too long
            minutes = duration / 60
            feedback_parts.append(f"⚠️ Duration set to {duration}s ({minutes:.1f} min) - too long")
            feedback_parts.append(f"  Expected: ~2700 seconds (45 minutes)")
            score += 10  # Partial credit
    
    # Criterion 4: Verify quit behavior with --play-and-exit or vlc://quit (10 points)
    quit_configured = False
    
    if result_data and result_data.get('quit_configured'):
        quit_configured = True
    elif '--play-and-exit' in all_content or 'vlc://quit' in all_content:
        quit_configured = True
    
    if quit_configured:
        feedback_parts.append("✅ VLC configured to quit after playback (--play-and-exit or vlc://quit)")
        score += 10
    else:
        feedback_parts.append("⚠️ No explicit quit instruction found (--play-and-exit)")
        feedback_parts.append("  --run-time alone will stop playback but may not close VLC")
        # Don't penalize heavily as --run-time might quit depending on version
    
    # Criterion 5: Verify completion marker exists (10 points)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_sleep_timer_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        
        if 'Runtime captured: true' in marker_content or 'Runtime captured: True' in marker_content:
            feedback_parts.append("✅ Task completion verified")
            score += 10
        else:
            feedback_parts.append("⚠️ Task may not have completed successfully")
            score += 5
        
        os.unlink(temp_marker.name)
    except Exception as e:
        logger.warning(f"Could not read completion marker: {e}")
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Bonus: Check for evidence of testing/validation (bonus 5 points, capped at 100)
    if re.search(r'--run-time[=\s]+\d{1,3}\b', all_content):  # Short test duration (< 1000s)
        feedback_parts.append("✓ Evidence of testing with short duration found (good practice!)")
        score = min(score + 5, max_score)
    
    # Determine success
    # Need: correct video + runtime configured + duration approximately correct
    success = video_file_correct and runtime_configured and (correct_duration or duration >= 60)
    
    # Alternative success: partial credit if close
    if score >= 60.0:
        success = True
    
    # Add helpful guidance if failed
    if not success:
        feedback_parts.append("")
        feedback_parts.append("💡 Hint: Use 'vlc --run-time=2700 --play-and-exit /home/ga/Videos/relaxing_thunderstorm.mp4'")
        feedback_parts.append("   Or: 'cvlc --run-time=2700 --play-and-exit /home/ga/Videos/relaxing_thunderstorm.mp4'")
        feedback_parts.append("   For testing: 'vlc --run-time=30 --play-and-exit /home/ga/Videos/relaxing_thunderstorm.mp4'")
    
    feedback = "\n".join(feedback_parts)
    
    result = {
        "passed": success,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "video_correct": video_file_correct,
            "runtime_configured": runtime_configured,
            "duration_seconds": duration,
            "duration_correct": correct_duration,
            "quit_configured": quit_configured
        }
    }
    
    logger.info(f"Verification result: {score:.1f}/{max_score} points, Passed: {success}")
    return result
