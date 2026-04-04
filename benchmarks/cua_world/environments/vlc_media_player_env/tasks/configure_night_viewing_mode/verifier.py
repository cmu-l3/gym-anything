#!/usr/bin/env python3
"""
Verifier for Configure Night Viewing Mode task
"""

import sys
import os
import logging
import tempfile
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_night_viewing_mode(traj, env_info, task_info):
    """
    Verify VLC is configured with night viewing mode adjustments.
    
    Checks:
    1. Image adjust filter is enabled
    2. Brightness OR gamma is reduced to appropriate level (0.5-0.8)
    3. Settings persist in config file
    4. BONUS: Warm color filter applied (hue adjustment)
    
    Returns:
        Dict with "passed", "score", "feedback"
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy VLC config from container
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    temp_config_path = temp_config.name
    temp_config.close()
    
    try:
        copy_from_env("/tmp/vlc_night_mode_config.txt", temp_config_path)
    except Exception as e:
        logger.error(f"Error copying config: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not access VLC config: {str(e)}"}
    
    if not os.path.exists(temp_config_path):
        return {"passed": False, "score": 0, "feedback": "VLC config file not found"}
    
    # Check if config is just an error message
    with open(temp_config_path, 'r') as f:
        first_line = f.readline().strip()
        if first_line == "Config not found":
            os.unlink(temp_config_path)
            return {"passed": False, "score": 0, "feedback": "VLC config file not found in container"}
    
    # Parse VLC config
    config = parse_vlc_config(temp_config_path)
    
    if not config:
        os.unlink(temp_config_path)
        return {"passed": False, "score": 0, "feedback": "Failed to parse VLC config"}
    
    # Criterion 1: Check if image adjust filter is enabled
    image_adjust_enabled = False
    
    # Check video-filter setting
    video_filter = config.get('video-filter', '')
    video_splitter = config.get('video-splitter', '')
    
    if 'adjust' in video_filter.lower() or 'adjust' in video_splitter.lower():
        image_adjust_enabled = True
        feedback_parts.append("✅ Image adjust filter enabled")
    
    # Alternative: check for adjust-enabled flag
    if config.get('adjust-enabled') == '1' or config.get('adjust-activate') == '1':
        image_adjust_enabled = True
        if not any('Image adjust filter enabled' in f for f in feedback_parts):
            feedback_parts.append("✅ Image adjust filter enabled")
    
    if not image_adjust_enabled:
        # Check if any adjustment values are present (implicit activation)
        adjustment_keys = ['brightness', 'gamma', 'contrast', 'saturation', 'hue']
        has_adjustments = any(key in config for key in adjustment_keys)
        
        if has_adjustments:
            image_adjust_enabled = True
            feedback_parts.append("✅ Video adjustments found (filter implicitly enabled)")
    
    if image_adjust_enabled:
        criteria_met += 1
    else:
        feedback_parts.append("❌ Image adjust filter not enabled")
        os.unlink(temp_config_path)
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": " | ".join(feedback_parts)
        }
    
    # Criterion 2: Check brightness/gamma reduction
    brightness_reduced = False
    gamma_reduced = False
    
    # Check brightness (default is 1.0, we want 0.5-0.8)
    if 'brightness' in config:
        try:
            brightness = float(config['brightness'])
            if 0.4 <= brightness <= 0.85:
                brightness_reduced = True
                feedback_parts.append(f"✅ Brightness reduced to {brightness:.2f} (good for night viewing)")
            elif brightness < 0.4:
                brightness_reduced = True  # Still counts, but warn
                feedback_parts.append(f"⚠️ Brightness very low ({brightness:.2f}) - may be too dark")
            elif brightness > 0.85 and brightness < 0.95:
                feedback_parts.append(f"⚠️ Brightness only slightly reduced ({brightness:.2f})")
            else:
                feedback_parts.append(f"❌ Brightness not reduced ({brightness:.2f})")
        except (ValueError, TypeError):
            logger.warning(f"Invalid brightness value: {config['brightness']}")
    
    # Check gamma (default is 1.0, we want 0.5-0.85)
    if 'gamma' in config:
        try:
            gamma = float(config['gamma'])
            if 0.4 <= gamma <= 0.9:
                gamma_reduced = True
                feedback_parts.append(f"✅ Gamma reduced to {gamma:.2f} (good for night viewing)")
            elif gamma < 0.4:
                gamma_reduced = True  # Still counts, but warn
                feedback_parts.append(f"⚠️ Gamma very low ({gamma:.2f}) - may be too dark")
            elif gamma > 0.9 and gamma < 0.98:
                feedback_parts.append(f"⚠️ Gamma only slightly reduced ({gamma:.2f})")
            else:
                feedback_parts.append(f"❌ Gamma not reduced ({gamma:.2f})")
        except (ValueError, TypeError):
            logger.warning(f"Invalid gamma value: {config['gamma']}")
    
    # Must have brightness OR gamma reduced
    if brightness_reduced or gamma_reduced:
        criteria_met += 2  # Double weight for main criterion
    else:
        feedback_parts.append("❌ Neither brightness nor gamma adequately reduced")
    
    # Criterion 3: Check for warm color filter (BONUS)
    warm_filter_applied = False
    
    if 'hue' in config:
        try:
            hue = int(config['hue'])
            # Hue range is typically -180 to 180
            # Slight positive values shift toward red/yellow (warm)
            # We're lenient here - any non-zero adjustment counts
            if hue != 0 and abs(hue) <= 90:
                warm_filter_applied = True
                feedback_parts.append(f"✅ BONUS: Hue adjusted to {hue} (warm tone filter)")
        except (ValueError, TypeError):
            logger.warning(f"Invalid hue value: {config['hue']}")
    
    # Check contrast/saturation adjustments (alternative approach to warm colors)
    if not warm_filter_applied:
        if 'contrast' in config or 'saturation' in config:
            try:
                contrast = float(config.get('contrast', 1.0))
                saturation = float(config.get('saturation', 1.0))
                if contrast != 1.0 or saturation != 1.0:
                    feedback_parts.append(f"⚠️ Additional adjustments found (contrast: {contrast}, saturation: {saturation})")
            except (ValueError, TypeError):
                pass
    
    os.unlink(temp_config_path)
    
    # Calculate final score
    base_score = (criteria_met / total_criteria) * 100
    
    # Add bonus points for warm filter
    if warm_filter_applied:
        base_score = min(100, base_score + 10)
        feedback_parts.append("🌟 Bonus points for warm color filter!")
    else:
        feedback_parts.append("⚠️ No warm color adjustment (optional but recommended for blue light reduction)")
    
    score = int(base_score)
    passed = score >= 80
    
    # Create overall feedback message
    if passed:
        if warm_filter_applied:
            overall_msg = "SUCCESS: Night viewing mode excellently configured with warm filter!"
        else:
            overall_msg = "SUCCESS: Night viewing mode properly configured"
    else:
        overall_msg = f"PARTIAL: Night mode incomplete (score: {score}/100)"
    
    feedback = overall_msg + " | " + " | ".join(feedback_parts)
    
    # Check completion marker for extra validation
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_night_mode_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        if "completed" in marker_content.lower():
            logger.info("✅ Task completion marker verified")
        os.unlink(temp_marker.name)
    except Exception:
        logger.warning("⚠️ Completion marker not found (non-critical)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
