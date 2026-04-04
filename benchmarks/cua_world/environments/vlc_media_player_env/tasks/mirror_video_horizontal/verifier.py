#!/usr/bin/env python3
"""
Verifier for Mirror Video Horizontal task

Checks if VLC has horizontal flip transformation applied by examining
the vlcrc configuration file for transform filter settings.
"""

import sys
import os
import logging
import tempfile

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_transform_filter_enabled(config):
    """
    Check if transform filter is enabled in VLC config.
    
    Transform filter can be in either video-filter or vout-filter settings.
    
    Args:
        config: Dict of VLC config key-value pairs
        
    Returns:
        Tuple of (bool: filter_enabled, str: which_setting)
    """
    video_filter = config.get('video-filter', '').lower()
    vout_filter = config.get('vout-filter', '').lower()
    
    logger.info(f"video-filter = '{video_filter}'")
    logger.info(f"vout-filter = '{vout_filter}'")
    
    if 'transform' in video_filter:
        return True, 'video-filter'
    elif 'transform' in vout_filter:
        return True, 'vout-filter'
    
    return False, ''


def check_horizontal_flip_type(config):
    """
    Check if the transform type is specifically horizontal flip.
    
    VLC transform types include:
    - hflip (horizontal flip)
    - vflip (vertical flip)
    - 90, 180, 270 (rotations)
    - flip-horizontal, mirror (alternate names)
    
    Args:
        config: Dict of VLC config key-value pairs
        
    Returns:
        Tuple of (bool: is_horizontal_flip, str: transform_type)
    """
    transform_type = config.get('transform-type', '').lower()
    
    logger.info(f"transform-type = '{transform_type}'")
    
    # Check for various horizontal flip identifiers
    horizontal_flip_keywords = ['hflip', 'flip-horizontal', 'horizontal', 'mirror']
    
    # Should NOT be vertical flip or rotation
    invalid_keywords = ['vflip', 'vertical', '90', '180', '270']
    
    # Check if it's horizontal flip
    is_horizontal = any(keyword in transform_type for keyword in horizontal_flip_keywords)
    
    # Make sure it's not a vertical flip or rotation
    is_invalid = any(keyword in transform_type for keyword in invalid_keywords)
    
    if is_horizontal and not is_invalid:
        return True, transform_type
    elif transform_type and not is_invalid:
        # Some transform is set, but unclear if horizontal
        # Give partial credit if transform filter is at least enabled
        return False, transform_type
    
    return False, transform_type


def verify_mirror_video_horizontal(traj, env_info, task_info):
    """
    Verify mirror video horizontal task completion.
    
    Checks:
    1. VLC config file exists and is parseable
    2. Transform filter is enabled (video-filter or vout-filter)
    3. Transform type is horizontal flip (not rotation or vertical flip)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task information (not used)
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    logger.info("=" * 60)
    logger.info("Verifying mirror_video_horizontal task...")
    logger.info("=" * 60)
    
    # Copy VLC config from container
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='_vlcrc')
    
    try:
        copy_from_env("/tmp/vlc_mirror_result_vlcrc", temp_config.name)
        logger.info(f"✅ VLC config copied to {temp_config.name}")
    except Exception as e:
        logger.error(f"Failed to copy VLC config: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to copy VLC config: {str(e)}"
        }
    
    # Check if config file is valid (not placeholder)
    try:
        config_size = os.path.getsize(temp_config.name)
        if config_size < 20:
            with open(temp_config.name, 'r') as f:
                content = f.read().strip()
            if content in ['missing_config', 'missing', '']:
                os.unlink(temp_config.name)
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "❌ VLC configuration file not found or empty"
                }
    except Exception as e:
        logger.error(f"Error checking config file: {e}")
        os.unlink(temp_config.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error reading config file: {str(e)}"
        }
    
    # Criterion 1: Parse VLC config
    try:
        config = parse_vlc_config(temp_config.name)
        logger.info(f"✅ Parsed VLC config with {len(config)} entries")
        
        criteria_met += 1
        feedback_parts.append("✅ Config accessible")
        
        # Log all relevant settings
        relevant_keys = ['video-filter', 'vout-filter', 'transform-type']
        for key in relevant_keys:
            if key in config:
                logger.info(f"  {key} = {config[key]}")
        
    except Exception as e:
        logger.error(f"Failed to parse VLC config: {e}", exc_info=True)
        os.unlink(temp_config.name)
        return {
            "passed": False,
            "score": 33,
            "feedback": f"⚠️ Config found but failed to parse: {str(e)}"
        }
    
    # Criterion 2: Check if transform filter is enabled
    filter_enabled, filter_setting = check_transform_filter_enabled(config)
    
    if filter_enabled:
        criteria_met += 1
        feedback_parts.append(f"✅ Transform filter enabled (in {filter_setting})")
        logger.info(f"✅ Transform filter found in {filter_setting}")
    else:
        feedback_parts.append("❌ Transform filter not enabled")
        logger.warning("Transform filter not found in video-filter or vout-filter")
        os.unlink(temp_config.name)
        
        # Provide helpful hint
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": " | ".join(feedback_parts) + 
                       "\n\nHint: Go to Tools → Effects and Filters → Video Effects → Geometry → Enable 'Transform'"
        }
    
    # Criterion 3: Check if transform type is horizontal flip
    is_hflip, transform_type = check_horizontal_flip_type(config)
    
    if is_hflip:
        criteria_met += 1
        feedback_parts.append(f"✅ Horizontal flip applied (type: {transform_type})")
        logger.info(f"✅ Horizontal flip confirmed: {transform_type}")
    else:
        if transform_type:
            feedback_parts.append(f"⚠️ Transform enabled but wrong type (got: {transform_type}, expected: hflip/horizontal)")
            logger.warning(f"Wrong transform type: {transform_type}")
            
            # Provide specific feedback
            if any(kw in transform_type for kw in ['90', '180', '270']):
                feedback_parts.append("Note: Rotation applied instead of flip")
            elif 'vflip' in transform_type or 'vertical' in transform_type:
                feedback_parts.append("Note: Vertical flip applied instead of horizontal")
        else:
            feedback_parts.append("❌ Transform type not set (expected: hflip/horizontal)")
            logger.warning("Transform filter enabled but transform-type not set")
    
    # Clean up temp file
    os.unlink(temp_config.name)
    
    # Check completion marker (bonus, not counted in criteria)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_mirror_completed.txt", temp_marker.name)
        logger.info("✅ Completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        logger.info("⚠️ Completion marker not found (non-critical)")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    # Add success message with context
    if passed:
        feedback += "\n\n✅ Perfect! The video is now mirrored horizontally. " \
                   "This makes it easier to follow along with tutorials where the instructor faces the camera. " \
                   "When you look at the screen, the instructor's movements now match your mirror reflection."
    
    logger.info("=" * 60)
    logger.info(f"Verification Result: {'PASSED' if passed else 'FAILED'}")
    logger.info(f"Score: {score}% ({criteria_met}/{total_criteria} criteria met)")
    logger.info(f"Feedback: {feedback}")
    logger.info("=" * 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
