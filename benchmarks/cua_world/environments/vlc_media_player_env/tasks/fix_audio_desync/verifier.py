#!/usr/bin/env python3
"""
Verifier for Fix Audio Desync task

Checks:
1. Result file exists and is parseable
2. Audio desync value is within tolerance of target
3. Setting was actually changed from initial value
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


def verify_fix_audio_desync(traj, env_info, task_info):
    """
    Verify fix audio desync task completion.
    
    Checks:
    1. Result file exists and is parseable
    2. Audio desync setting is within tolerance of target
    3. Setting persisted in configuration
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task parameters including target_delay_ms
    
    Returns:
        dict with 'passed', 'score', and 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Get task parameters
    task_params = task_info.get('params', {})
    target_delay_ms = task_params.get('target_delay_ms', 250)
    tolerance_ms = task_params.get('tolerance_ms', 50)
    
    # Criterion 1: Copy and parse result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        try:
            copy_from_env("/tmp/vlc_desync_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying desync result: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Result file not found: {str(e)}"
            }
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        criteria_met += 1
        feedback_parts.append("✅ Result file accessible")
        
        # Extract values
        actual_desync = result.get('audio_desync_ms', 0)
        config_source = result.get('config_source', 'unknown')
        
        feedback_parts.append(f"Audio desync: {actual_desync}ms (source: {config_source})")
        
        # Criterion 2: Check if value is within tolerance of target
        deviation = abs(actual_desync - target_delay_ms)
        
        if deviation <= tolerance_ms:
            criteria_met += 2  # Double weight for main criterion
            feedback_parts.append(
                f"✅ Desync correctly set (target: {target_delay_ms}ms, "
                f"actual: {actual_desync}ms, deviation: {deviation}ms)"
            )
        else:
            # Partial credit if at least the value was changed from 0
            if actual_desync != 0:
                criteria_met += 0.5
                feedback_parts.append(
                    f"⚠️ Desync adjusted but not at target "
                    f"(target: {target_delay_ms}ms, actual: {actual_desync}ms, "
                    f"deviation: {deviation}ms exceeds tolerance {tolerance_ms}ms)"
                )
            else:
                feedback_parts.append(
                    f"❌ Desync not adjusted from default "
                    f"(expected {target_delay_ms}ms ±{tolerance_ms}ms, got {actual_desync}ms)"
                )
        
        os.unlink(temp_result.name)
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid result file format: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading result: {str(e)}"
        }
    
    # Criterion 3: Verify config was actually saved (check completion marker)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_desync_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        
        if "Audio desync:" in marker_content:
            # Don't add to criteria_met since it's already counted above
            feedback_parts.append("✅ Configuration persisted")
        
        os.unlink(temp_marker.name)
    except Exception as e:
        feedback_parts.append("⚠️ Completion marker not found")
        logger.warning(f"Completion marker not found: {e}")
    
    # Optional: Also verify by reading the actual vlcrc file
    temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_desync_vlcrc_final.txt", temp_vlcrc.name)
        
        with open(temp_vlcrc.name, 'r') as f:
            vlcrc_content = f.read()
        
        # Look for audio-desync line
        for line in vlcrc_content.split('\n'):
            if line.startswith('audio-desync='):
                vlcrc_value = line.split('=')[1].strip()
                try:
                    vlcrc_desync = int(vlcrc_value)
                    logger.info(f"Verified from vlcrc: audio-desync={vlcrc_desync}")
                except ValueError:
                    logger.warning(f"Invalid value in vlcrc: {vlcrc_value}")
                break
        
        os.unlink(temp_vlcrc.name)
    except Exception as e:
        logger.warning(f"Could not verify vlcrc directly: {e}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }