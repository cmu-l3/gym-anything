#!/usr/bin/env python3
"""
Verifier for Correct Lens Distortion task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    parse_vlc_config,
    verify_snapshot_exists,
    verify_image_quality,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_correct_lens_distortion(traj, env_info, task_info):
    """
    Verify lens distortion correction task completion.
    
    Checks:
    1. Geometry/transform filter enabled in VLC config
    2. Corrected snapshot exists
    3. Snapshot has good quality
    
    Returns:
        Dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Criterion 1: Check if geometry filter is enabled (50% weight)
    # This is the main task requirement
    config_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    filter_enabled = False
    
    try:
        copy_from_env("/tmp/vlc_distortion_config.txt", config_temp.name)
        
        if os.path.exists(config_temp.name):
            config = parse_vlc_config(config_temp.name)
            
            # Check for geometry/transform filters
            video_filter = config.get('video-filter', '').lower()
            vout_filter = config.get('vout-filter', '').lower()
            
            geometry_keywords = ['transform', 'geometry', 'panoramix', 'ball', 'lens']
            
            filter_enabled = any(
                keyword in video_filter or keyword in vout_filter
                for keyword in geometry_keywords
            )
            
            if filter_enabled:
                criteria_met += 1.5  # Higher weight for main criterion
                detected_filters = [kw for kw in geometry_keywords if kw in video_filter or kw in vout_filter]
                feedback_parts.append(f"✅ Geometry filter enabled ({', '.join(detected_filters)})")
                logger.info(f"Detected filters - video-filter: {video_filter}, vout-filter: {vout_filter}")
            else:
                feedback_parts.append("❌ No geometry correction filter detected in config")
                logger.warning(f"No geometry filters found - video-filter: {video_filter}, vout-filter: {vout_filter}")
        else:
            feedback_parts.append("❌ VLC config not accessible")
        
        os.unlink(config_temp.name)
        
    except Exception as e:
        logger.error(f"Error checking VLC config: {e}", exc_info=True)
        feedback_parts.append(f"❌ Error reading VLC config: {str(e)}")
    
    # Criterion 2: Check if snapshot exists (30% weight)
    snapshot_exists = False
    
    try:
        success, file_info, error = setup_verification_environment(
            copy_from_env,
            "/tmp/vlc_corrected_snapshot.png",
            file_type='image'
        )
        
        if success:
            snapshot_exists = True
            criteria_met += 1
            image_data = file_info.get('data', {})
            size_kb = image_data.get('size_kb', 0)
            feedback_parts.append(f"✅ Snapshot captured ({size_kb:.1f} KB)")
            
            cleanup_verification_environment(file_info.get('temp_dir'))
        else:
            feedback_parts.append(f"❌ Snapshot not found: {error}")
            logger.warning(f"Snapshot not found: {error}")
    
    except Exception as e:
        logger.error(f"Error verifying snapshot: {e}", exc_info=True)
        feedback_parts.append(f"❌ Error checking snapshot: {str(e)}")
    
    # Criterion 3: Check snapshot quality (20% weight)
    if snapshot_exists:
        try:
            success, file_info, error = setup_verification_environment(
                copy_from_env,
                "/tmp/vlc_corrected_snapshot.png",
                file_type='image'
            )
            
            if success:
                image_data = file_info.get('data', {})
                
                # Check if snapshot has reasonable size (not a tiny error image)
                if image_data.get('size_kb', 0) > 50:
                    criteria_met += 0.5
                    
                    # Check resolution if available
                    if image_data.get('width', 0) > 640:
                        feedback_parts.append(f"✅ Snapshot quality good ({image_data.get('width')}x{image_data.get('height')})")
                    else:
                        feedback_parts.append(f"⚠️ Snapshot resolution low ({image_data.get('width')}x{image_data.get('height')})")
                else:
                    feedback_parts.append(f"⚠️ Snapshot file too small ({image_data.get('size_kb', 0):.1f} KB)")
                
                cleanup_verification_environment(file_info.get('temp_dir'))
        
        except Exception as e:
            logger.error(f"Error checking snapshot quality: {e}", exc_info=True)
            feedback_parts.append("⚠️ Could not verify snapshot quality")
    
    # Check completion marker (bonus, doesn't affect main score)
    try:
        marker_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/vlc_distortion_completed.txt", marker_temp.name)
        
        with open(marker_temp.name, 'r') as f:
            content = f.read()
        
        if "completed" in content.lower():
            feedback_parts.append("✅ Task completion verified")
        
        os.unlink(marker_temp.name)
    except Exception:
        logger.debug("Completion marker not found (not critical)")
    
    # Calculate score
    # Total possible: 1.5 + 1 + 0.5 = 3.0
    score = int((criteria_met / total_criteria) * 100)
    
    # Need at least filter enabled + snapshot to pass
    passed = filter_enabled and snapshot_exists and score >= 80
    
    feedback_parts.append(f"\n{'='*50}")
    feedback_parts.append(f"Total Score: {score}/100")
    feedback_parts.append(f"Status: {'✅ PASS' if passed else '❌ FAIL'}")
    
    if not filter_enabled and not snapshot_exists:
        feedback_parts.append("⚠️ Neither filter nor snapshot detected - task incomplete")
    elif not filter_enabled:
        feedback_parts.append("⚠️ Filter not enabled - main task requirement not met")
    elif not snapshot_exists:
        feedback_parts.append("⚠️ Snapshot not captured - cannot verify correction")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
