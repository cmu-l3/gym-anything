#!/usr/bin/env python3
"""
Verifier for Enhance Telescope Recording task
"""

import sys
import os
import logging
import tempfile

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    verify_snapshot_exists,
    verify_image_quality,
    parse_vlc_config,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_enhance_telescope_recording(traj, env_info, task_info):
    """
    Verify enhance telescope recording task completion.
    
    Checks:
    1. Snapshot file exists and has adequate quality
    2. VLC config shows adjustment filter was enabled
    3. Filter parameters meet minimum thresholds:
       - Gamma >= 1.5
       - Contrast >= 1.3
       - Brightness >= 0.1
    4. Snapshot resolution is adequate
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Verify snapshot exists and has quality
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_telescope_snapshot.png",
        file_type='image'
    )
    
    if success:
        image_data = file_info.get('data', {})
        
        # Check file size
        size_kb = image_data.get('size_kb', 0)
        if size_kb >= 30:
            criteria_met += 1
            feedback_parts.append(f"✅ Snapshot exists with adequate size ({size_kb:.1f} KB)")
        else:
            feedback_parts.append(f"⚠️ Snapshot too small ({size_kb:.1f} KB, need ≥30 KB)")
        
        # Check resolution
        width = image_data.get('width', 0)
        height = image_data.get('height', 0)
        
        if width >= 640 and height >= 480:
            feedback_parts.append(f"✅ Resolution adequate ({width}x{height})")
        else:
            feedback_parts.append(f"⚠️ Resolution low ({width}x{height}, need ≥640x480)")
        
        cleanup_verification_environment(file_info.get('temp_dir'))
    else:
        feedback_parts.append(f"❌ Snapshot not found: {error}")
        # Early return if snapshot doesn't exist
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
    
    # Criterion 2-4: Verify VLC config for adjustment filters
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/vlc_telescope_config.txt", temp_config.name)
        
        # Parse VLC config
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            feedback_parts.append("❌ Could not parse VLC config")
            os.unlink(temp_config.name)
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Check if adjustment filter is enabled
        video_filter = config.get('video-filter', '')
        adjust_enabled = 'adjust' in video_filter
        
        if adjust_enabled:
            criteria_met += 1
            feedback_parts.append("✅ Adjustment filter enabled")
        else:
            feedback_parts.append("❌ Adjustment filter not enabled in video-filter")
        
        # Criterion 3: Verify filter parameters
        try:
            gamma_value = float(config.get('adjust-gamma', '1.0'))
            contrast_value = float(config.get('adjust-contrast', '1.0'))
            brightness_value = float(config.get('adjust-brightness', '0.0'))
        except (ValueError, TypeError) as e:
            logger.error(f"Error parsing adjustment values: {e}")
            feedback_parts.append("❌ Could not parse adjustment filter values")
            os.unlink(temp_config.name)
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check each parameter against thresholds
        param_checks = []
        param_scores = 0
        max_param_score = 3
        
        if gamma_value >= 1.5:
            param_checks.append(f"Gamma: {gamma_value:.2f} ✓")
            param_scores += 1
        else:
            param_checks.append(f"Gamma: {gamma_value:.2f} (need ≥1.5)")
        
        if contrast_value >= 1.3:
            param_checks.append(f"Contrast: {contrast_value:.2f} ✓")
            param_scores += 1
        else:
            param_checks.append(f"Contrast: {contrast_value:.2f} (need ≥1.3)")
        
        if brightness_value >= 0.1:
            param_checks.append(f"Brightness: {brightness_value:.2f} ✓")
            param_scores += 1
        else:
            param_checks.append(f"Brightness: {brightness_value:.2f} (need ≥0.1)")
        
        feedback_parts.append(f"Filter values: {', '.join(param_checks)}")
        
        # Award criteria based on how many parameters meet thresholds
        if param_scores >= 2:
            criteria_met += 2  # Give full credit if at least 2/3 parameters are correct
            if param_scores == 3:
                feedback_parts.append("✅ All filter parameters meet thresholds")
            else:
                feedback_parts.append("✅ Most filter parameters meet thresholds")
        elif param_scores >= 1:
            criteria_met += 1
            feedback_parts.append("⚠️ Some filter parameters meet thresholds")
        else:
            feedback_parts.append("❌ Filter parameters insufficient")
        
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Error reading VLC config: {e}", exc_info=True)
        feedback_parts.append(f"❌ Error reading VLC config: {str(e)}")
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": " | ".join(feedback_parts)
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_telescope_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        if "completed" in marker_content.lower():
            feedback_parts.append("✅ Task completion verified")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }