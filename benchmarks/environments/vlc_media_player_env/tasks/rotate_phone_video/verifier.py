#!/usr/bin/env python3
"""
Verifier for rotate_phone_video@1
Checks if video rotation transform has been applied correctly in VLC
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path
from typing import Tuple, Dict, Any

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config, logger

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)


def parse_video_filter_string(filter_string: str) -> list:
    """
    Parse VLC video-filter or vout-filter string.
    Filters can be comma-separated or colon-separated.
    
    Example: "adjust:transform:deinterlace"
    Returns: ["adjust", "transform", "deinterlace"]
    """
    if not filter_string:
        return []
    
    # Split by common separators
    filters = re.split(r'[,:]', filter_string)
    return [f.strip() for f in filters if f.strip()]


def check_transform_enabled(config: Dict[str, str]) -> Tuple[bool, str]:
    """
    Check if transform filter is enabled in VLC config.
    
    Returns:
        (is_enabled, filter_location)
    """
    video_filter = config.get('video-filter', '')
    vout_filter = config.get('vout-filter', '')
    
    logger.info(f"Checking filters - video-filter: '{video_filter}', vout-filter: '{vout_filter}'")
    
    # Parse filter strings
    video_filters = parse_video_filter_string(video_filter)
    vout_filters = parse_video_filter_string(vout_filter)
    
    # Check if transform is in either filter list
    if 'transform' in video_filters:
        return True, 'video-filter'
    elif 'transform' in vout_filters:
        return True, 'vout-filter'
    
    # Fallback: check if 'transform' appears anywhere in the strings
    if 'transform' in video_filter.lower():
        return True, 'video-filter (substring match)'
    elif 'transform' in vout_filter.lower():
        return True, 'vout-filter (substring match)'
    
    return False, ''


def check_rotation_angle(config: Dict[str, str]) -> Tuple[bool, str, str]:
    """
    Check if rotation angle is correct.
    
    VLC uses transform-type setting with values like:
    - "90" or "rotate-90" for 90° counter-clockwise
    - "270" or "rotate-270" for 270° clockwise (equivalent to 90° CCW)
    
    Returns:
        (is_correct, transform_type_value, description)
    """
    transform_type = config.get('transform-type', '').strip()
    
    logger.info(f"Transform type: '{transform_type}'")
    
    if not transform_type:
        return False, '', 'No rotation angle set'
    
    # Normalize for comparison
    transform_lower = transform_type.lower()
    
    # Valid rotations for our task (90° CCW or 270° CW)
    valid_patterns = [
        ('90', '90° counter-clockwise'),
        ('270', '270° clockwise (equivalent to 90° CCW)'),
        ('rotate-90', '90° counter-clockwise'),
        ('rotate-270', '270° clockwise'),
        ('rotate by 90 degrees', '90° counter-clockwise'),
        ('rotate by 270 degrees', '270° clockwise'),
    ]
    
    for pattern, description in valid_patterns:
        if pattern in transform_lower:
            return True, transform_type, description
    
    # Check if it's a different rotation (incorrect)
    if any(x in transform_lower for x in ['180', 'rotate-180', 'flip', 'flop', 'transpose', 'antitranspose']):
        return False, transform_type, f'Wrong transformation: {transform_type}'
    
    return False, transform_type, f'Unknown transformation: {transform_type}'


def verify_rotate_phone_video(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that video rotation has been correctly applied in VLC.
    
    Checks:
    1. VLC config file is accessible
    2. Transform filter is enabled
    3. Rotation angle is correct (90° or 270°)
    
    Args:
        traj: Agent trajectory (unused for config-based verification)
        env_info: Environment info containing copy_from_env function
        task_info: Task information (unused)
    
    Returns:
        Dict with keys: passed, score, feedback
    """
    
    logger.info("=" * 70)
    logger.info("Starting rotate_phone_video verification")
    logger.info("=" * 70)
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        logger.error("copy_from_env function not available")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Error: Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy VLC config from container
    temp_config = tempfile.NamedTemporaryFile(mode='w+', delete=False, suffix='_vlcrc')
    temp_config_path = temp_config.name
    temp_config.close()
    
    try:
        # Criterion 1: Copy and parse VLC config
        try:
            copy_from_env("/tmp/vlcrc", temp_config_path)
            logger.info(f"VLC config copied to {temp_config_path}")
        except Exception as e:
            logger.error(f"Failed to copy VLC config: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ VLC configuration file not found. Did you open VLC? Error: {str(e)}"
            }
        
        # Check if file exists and has content
        if not os.path.exists(temp_config_path) or os.path.getsize(temp_config_path) == 0:
            logger.error("Config file is empty or doesn't exist")
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC configuration file is empty or not found"
            }
        
        # Parse configuration
        config = parse_vlc_config(temp_config_path)
        logger.info(f"Parsed VLC config: {len(config)} settings found")
        
        if not config:
            logger.warning("Config file parsed but appears empty")
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC configuration file is empty or corrupted"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")
        logger.info("Criterion 1 passed: Config accessible")
        
        # Criterion 2: Check if transform filter is enabled
        transform_enabled, filter_location = check_transform_enabled(config)
        
        if not transform_enabled:
            logger.warning("Transform filter not enabled")
            
            # Check if any video filters are set
            video_filter = config.get('video-filter', '')
            vout_filter = config.get('vout-filter', '')
            
            if video_filter or vout_filter:
                feedback_parts.append(
                    f"❌ Transform not enabled. Found filters: {video_filter or vout_filter} | "
                    f"Hint: Tools → Effects and Filters → Video Effects → Geometry → Transform"
                )
                return {
                    "passed": False,
                    "score": 33,
                    "feedback": " | ".join(feedback_parts)
                }
            else:
                feedback_parts.append(
                    "❌ No video filters applied. "
                    "Hint: Tools → Effects and Filters → Video Effects → Geometry → Check 'Transform'"
                )
                return {
                    "passed": False,
                    "score": 33,
                    "feedback": " | ".join(feedback_parts)
                }
        
        criteria_met += 1
        feedback_parts.append(f"✅ Transform filter enabled ({filter_location})")
        logger.info(f"Criterion 2 passed: Transform enabled in {filter_location}")
        
        # Criterion 3: Check rotation angle
        angle_correct, transform_value, angle_description = check_rotation_angle(config)
        
        if not angle_correct:
            logger.warning(f"Incorrect rotation angle: {transform_value}")
            
            if not transform_value:
                feedback_parts.append(
                    "❌ Transform enabled but no rotation angle set. "
                    "Hint: Select 'Rotate by 90 degrees' or 'Rotate by 270 degrees' from Transform dropdown"
                )
                return {
                    "passed": False,
                    "score": 66,
                    "feedback": " | ".join(feedback_parts)
                }
            else:
                feedback_parts.append(
                    f"❌ Wrong rotation: {angle_description}. "
                    f"Hint: Video needs 90° CCW or 270° CW rotation to be upright"
                )
                return {
                    "passed": False,
                    "score": 66,
                    "feedback": " | ".join(feedback_parts)
                }
        
        criteria_met += 1
        feedback_parts.append(f"✅ Correct rotation applied: {angle_description}")
        logger.info(f"Criterion 3 passed: Correct rotation - {angle_description}")
        
        # All criteria met!
        logger.info("=" * 70)
        logger.info("✅ ALL CRITERIA MET - TASK SUCCESSFUL")
        logger.info("=" * 70)
        
        success_feedback = " | ".join(feedback_parts) + " | 🎉 Video successfully rotated to correct orientation!"
        
        return {
            "passed": True,
            "score": 100,
            "feedback": success_feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    finally:
        # Clean up temp file
        if os.path.exists(temp_config_path):
            try:
                os.unlink(temp_config_path)
                logger.debug(f"Cleaned up temp config: {temp_config_path}")
            except Exception as e:
                logger.warning(f"Failed to clean up temp file: {e}")


def verify_task(traj, env_info, task_info):
    """Entry point for gym-anything verifier."""
    return verify_rotate_phone_video(traj, env_info, task_info)
