#!/usr/bin/env python3
"""
Verifier for Add Timecode Overlay task
Checks if VLC timecode overlay is configured and optionally verified via screenshot
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_timecode_overlay(traj, env_info, task_info):
    """
    Verify add timecode overlay task completion.
    
    Checks:
    1. Timecode result file exists and is valid
    2. Timecode overlay is enabled in VLC configuration
    3. Optional verification evidence (screenshot or output video)
    
    Primary success criterion: timecode_enabled=true in config
    Bonus points: screenshot or output video as verification evidence
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy timecode result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_timecode_result.json", temp_result.name)
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        criteria_met += 1
        feedback_parts.append("✅ Timecode result accessible")
        
        # Get settings from result
        timecode_enabled = result.get('timecode_enabled', False)
        timecode_settings = result.get('timecode_settings', {})
        config_exists = result.get('config_file_exists', False)
        screenshot_found = result.get('screenshot_found', False)
        output_exists = result.get('output_video_exists', False)
        
        logger.info(f"Timecode enabled: {timecode_enabled}")
        logger.info(f"Config exists: {config_exists}")
        logger.info(f"Settings: {timecode_settings}")
        
        # Criterion 2: Timecode overlay enabled (MAIN CRITERION - double weight)
        if timecode_enabled:
            criteria_met += 2  # Double weight for main criterion
            
            # Provide details about which setting enabled it
            setting_details = []
            if isinstance(timecode_settings, dict):
                for key, value in timecode_settings.items():
                    if value and value != "0" and value != "":
                        setting_details.append(f"{key}={value}")
            
            if setting_details:
                settings_str = ", ".join(setting_details[:3])  # Show first 3 settings
                feedback_parts.append(f"✅ Timecode overlay enabled ({settings_str})")
            else:
                feedback_parts.append("✅ Timecode overlay enabled")
        else:
            feedback_parts.append("❌ Timecode overlay not enabled in configuration")
        
        # Criterion 3: Verification evidence (screenshot or output video) - OPTIONAL BONUS
        verification_evidence = []
        
        if screenshot_found:
            verification_evidence.append("screenshot")
            # Verify screenshot file was actually copied
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env("/tmp/vlc_timecode_screenshot.png", temp_screenshot.name)
                
                # Check screenshot size
                screenshot_size_kb = os.path.getsize(temp_screenshot.name) / 1024
                
                if screenshot_size_kb > 10:
                    criteria_met += 0.5  # Bonus points
                    verification_evidence.append(f"{screenshot_size_kb:.1f}KB")
                    logger.info(f"Screenshot verified: {screenshot_size_kb:.1f} KB")
                
                os.unlink(temp_screenshot.name)
            except Exception as e:
                logger.warning(f"Screenshot found but couldn't verify: {e}")
        
        if output_exists:
            verification_evidence.append("output_video")
            # Try to verify output video
            temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
            try:
                copy_from_env("/tmp/vlc_timecode_output.mp4", temp_output.name)
                
                output_size_mb = os.path.getsize(temp_output.name) / (1024 * 1024)
                
                if output_size_mb > 0.5:
                    criteria_met += 0.5  # Bonus points
                    verification_evidence.append(f"{output_size_mb:.1f}MB")
                    logger.info(f"Output video verified: {output_size_mb:.1f} MB")
                
                os.unlink(temp_output.name)
            except Exception as e:
                logger.warning(f"Output video found but couldn't verify: {e}")
        
        if verification_evidence:
            feedback_parts.append(f"✅ Verification evidence: {', '.join(verification_evidence)}")
        else:
            feedback_parts.append("⚠️ No verification evidence (screenshot/output) - acceptable")
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Error reading timecode result: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_timecode_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        
        if "completed" in marker_content.lower():
            feedback_parts.append("✅ Task completed")
        
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    # Total possible: 3 base + up to 1 bonus = 4 max
    # But normalize to 0-100 scale based on 3 criteria
    score = int((min(criteria_met, 3) / total_criteria) * 100)
    
    # Bonus points can push score slightly above if evidence provided
    if criteria_met > 3:
        score = min(100, score + 5)  # Small bonus for verification evidence
    
    # Pass threshold: 70% - must have config enabled
    passed = score >= 70 and timecode_enabled
    
    feedback = " | ".join(feedback_parts)
    
    # Final summary message
    if passed and criteria_met >= 3:
        summary = "✅ Task completed successfully! Timecode overlay configured and verified."
    elif passed:
        summary = "✅ Task completed. Timecode overlay configured."
    else:
        summary = "❌ Task incomplete. Timecode overlay not properly configured."
    
    feedback = f"{summary} | {feedback}"
    
    logger.info("=" * 60)
    logger.info(f"Final Result: {'SUCCESS' if passed else 'FAILURE'}")
    logger.info(f"Score: {score}")
    logger.info(f"Criteria met: {criteria_met}/{total_criteria} (+ bonus)")
    logger.info(f"Timecode enabled: {timecode_enabled}")
    logger.info("=" * 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
