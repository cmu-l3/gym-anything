#!/usr/bin/env python3
"""
Verifier for Configure Movement Analysis task
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


def parse_vlc_config_for_osd(vlcrc_path):
    """
    Parse VLC config file for OSD/time display settings.
    
    Args:
        vlcrc_path: Path to vlcrc file
        
    Returns:
        bool: True if OSD time display is enabled
    """
    try:
        with open(vlcrc_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Check for various OSD-related settings
        osd_patterns = [
            r'^qt-time-display=1',
            r'^qt-show-time=1',
            r'^osd=1',
            r'^video-title-show=0',  # Disabled title can indicate OSD preference
        ]
        
        for pattern in osd_patterns:
            if re.search(pattern, content, re.MULTILINE):
                logger.info(f"Found OSD setting matching: {pattern}")
                return True
        
        return False
        
    except Exception as e:
        logger.error(f"Error parsing vlcrc for OSD: {e}")
        return False


def verify_movement_analysis(traj, env_info, task_info):
    """
    Verify movement analysis configuration task completion.
    
    Checks:
    1. OSD time display enabled (from config)
    2. Playback speed in analysis range (0.5-0.75, or 50-75%)
    3. Overall workflow coherence
    
    Scoring:
    - OSD enabled: 40 points
    - Playback speed adjusted: 40 points
    - A-B loop evidence (bonus): 20 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Copy movement analysis result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_movement_analysis_result.json", temp_result.name)
    except Exception as e:
        logger.error(f"Error copying result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Result file not found: {str(e)}"}
    
    try:
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        feedback_parts.append("✅ Result file accessible")
        
        # Extract values
        playback_rate = float(result.get('playback_rate', 1.0))
        osd_enabled = result.get('osd_enabled', False)
        ab_loop_detected = result.get('ab_loop_detected', False)
        runtime_captured = result.get('runtime_captured', False)
        
        logger.info(f"Playback rate: {playback_rate}, OSD: {osd_enabled}, Loop: {ab_loop_detected}")
        
        # Criterion 1: OSD enabled (40 points)
        if osd_enabled:
            score += 40
            feedback_parts.append("✅ On-screen time display enabled")
        else:
            # Double-check by reading config file directly
            temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
            try:
                copy_from_env("/tmp/vlc_movement_vlcrc.conf", temp_vlcrc.name)
                if parse_vlc_config_for_osd(temp_vlcrc.name):
                    score += 40
                    feedback_parts.append("✅ On-screen time display enabled (verified from config)")
                    osd_enabled = True
                else:
                    feedback_parts.append("❌ Time display not configured")
                os.unlink(temp_vlcrc.name)
            except Exception:
                feedback_parts.append("❌ Time display not configured")
        
        # Criterion 2: Playback speed adjusted (40 points)
        # Target range: 0.5-0.75 (50-75%)
        # Also accept if speed is different from default (1.0)
        
        if 0.45 <= playback_rate <= 0.80:
            # Ideal range
            score += 40
            feedback_parts.append(f"✅ Playback speed optimal for analysis ({playback_rate:.2f}x = {int(playback_rate*100)}%)")
        elif playback_rate != 1.0 and 0.25 <= playback_rate <= 0.95:
            # Speed was adjusted, but not in optimal range
            score += 30
            feedback_parts.append(f"⚠️ Playback speed adjusted ({playback_rate:.2f}x) but not optimal (target: 50-75%)")
        elif runtime_captured and playback_rate == 1.0:
            # Speed not adjusted
            feedback_parts.append(f"❌ Playback speed not adjusted (still at {playback_rate:.2f}x)")
        else:
            # Could not determine speed, give partial credit if OSD is enabled
            if osd_enabled:
                score += 15
                feedback_parts.append("⚠️ Playback speed unclear (partial credit for OSD config)")
            else:
                feedback_parts.append("❌ Playback speed not verified")
        
        # Criterion 3: A-B loop evidence (20 bonus points)
        if ab_loop_detected:
            score += 20
            feedback_parts.append("✅ A-B loop configured (bonus)")
        else:
            feedback_parts.append("⚠️ A-B loop not detected (optional but recommended)")
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error parsing result: {str(e)}"}
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_movement_analysis_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Overall workflow assessment
    if osd_enabled and 0.4 <= playback_rate <= 0.9:
        feedback_parts.append("✅ Configuration suitable for movement analysis")
    elif osd_enabled or playback_rate != 1.0:
        feedback_parts.append("⚠️ Partial movement analysis configuration")
    
    # Calculate final score
    score = min(score, max_score)  # Cap at 100
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Final score: {score}/100, Passed: {passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "playback_rate": playback_rate,
            "osd_enabled": osd_enabled,
            "ab_loop_detected": ab_loop_detected,
        }
    }