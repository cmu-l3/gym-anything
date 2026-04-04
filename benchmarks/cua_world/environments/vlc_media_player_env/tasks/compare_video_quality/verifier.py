#!/usr/bin/env python3
"""
Verifier for Compare Video Quality task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    verify_image_quality,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compare_video_quality(traj, env_info, task_info):
    """
    Verify compare video quality task completion.
    
    Checks:
    1. Both screenshot files exist
    2. Both screenshots have reasonable quality (>50KB)
    3. Both screenshots are valid images with proper dimensions
    4. Screenshots were captured within reasonable time window
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Check both screenshots
    screenshot_paths = {
        'version_a': '/tmp/vlc_compare_screenshot_a.png',
        'version_b': '/tmp/vlc_compare_screenshot_b.png'
    }
    
    screenshots_info = {}
    
    for name, container_path in screenshot_paths.items():
        # Copy and verify screenshot
        success, file_info, error = setup_verification_environment(
            copy_from_env,
            container_path,
            file_type='image'
        )
        
        if not success:
            feedback_parts.append(f"❌ Screenshot {name} not found: {error}")
            screenshots_info[name] = None
            continue
        
        # Screenshot exists
        screenshots_info[name] = file_info
        
        image_data = file_info.get('data', {})
        filepath = image_data.get('filepath', '')
        
        # Check image quality
        if not verify_image_quality(filepath, min_size_kb=50):
            feedback_parts.append(f"⚠️ Screenshot {name} quality too low")
            cleanup_verification_environment(file_info.get('temp_dir'))
            continue
        
        # Check dimensions
        width = image_data.get('width', 0)
        height = image_data.get('height', 0)
        
        if width < 640 or height < 360:
            feedback_parts.append(f"⚠️ Screenshot {name} resolution too low: {width}x{height}")
            cleanup_verification_environment(file_info.get('temp_dir'))
            continue
        
        # This screenshot passes all checks
        criteria_met += 1
        size_kb = image_data.get('size_kb', 0)
        feedback_parts.append(f"✅ Screenshot {name} valid ({width}x{height}, {size_kb:.1f}KB)")
    
    # Criterion 3: Both screenshots exist and are valid
    if screenshots_info.get('version_a') and screenshots_info.get('version_b'):
        criteria_met += 1
        feedback_parts.append("✅ Both screenshots captured")
        
        # Criterion 4: Check if screenshots were taken close together in time
        try:
            filepath_a = screenshots_info['version_a']['data']['filepath']
            filepath_b = screenshots_info['version_b']['data']['filepath']
            
            stat_a = os.stat(filepath_a)
            stat_b = os.stat(filepath_b)
            
            time_diff = abs(stat_a.st_mtime - stat_b.st_mtime)
            
            if time_diff <= 120:  # Within 2 minutes
                criteria_met += 1
                feedback_parts.append(f"✅ Screenshots captured {time_diff:.1f}s apart (simultaneous comparison)")
            else:
                feedback_parts.append(f"⚠️ Screenshots captured {time_diff:.1f}s apart (may not be true comparison)")
        except Exception as e:
            logger.warning(f"Could not compare timestamps: {e}")
            feedback_parts.append("⚠️ Could not verify capture timing")
    else:
        feedback_parts.append("❌ Missing one or both screenshots")
    
    # Cleanup temp directories
    for name, file_info in screenshots_info.items():
        if file_info:
            cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_compare_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            content = f.read()
        if "completed" in content.lower():
            feedback_parts.append("✅ Task completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }