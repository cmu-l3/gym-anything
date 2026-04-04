#!/usr/bin/env python3
"""
Verifier for Configure Low Resource Playback task
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_low_resource_playback(traj, env_info, task_info):
    """
    Verify configure low resource playback task completion.
    
    Checks VLC configuration for performance optimization settings:
    1. Hardware acceleration enabled (CRITICAL - weight 2.0)
    2. Frame skipping enabled (HIGH - weight 1.5)
    3. Lightweight video output (MEDIUM - weight 1.0)
    4. Reduced caching (MEDIUM - weight 0.8)
    5. Video filters disabled (MEDIUM - weight 0.8)
    6. Skip late frames enabled (HIGH - weight 1.2)
    7. Deinterlacing disabled (LOW - weight 0.7)
    
    Weighted scoring system with 70% pass threshold.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria = {
        "hw_accel": {"met": False, "weight": 2.0, "feedback": ""},
        "frame_skip": {"met": False, "weight": 1.5, "feedback": ""},
        "video_output": {"met": False, "weight": 1.0, "feedback": ""},
        "cache_reduced": {"met": False, "weight": 0.8, "feedback": ""},
        "filters_disabled": {"met": False, "weight": 0.8, "feedback": ""},
        "skip_late": {"met": False, "weight": 1.2, "feedback": ""},
        "deinterlace_off": {"met": False, "weight": 0.7, "feedback": ""}
    }
    
    total_weight = sum(c["weight"] for c in criteria.values())
    feedback_parts = []
    
    # Copy VLC config file
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        # Copy config file
        try:
            copy_from_env("/tmp/vlc_lowres_config.txt", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying config file: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Config file not found: {str(e)}"}
        
        # Parse VLC config
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            return {"passed": False, "score": 0, "feedback": "Config file empty or invalid"}
        
        feedback_parts.append("✅ Config file accessible")
        
        # Criterion 1: Hardware Acceleration (MOST IMPORTANT)
        hw_accel = config.get('avcodec-hw', 'none').lower()
        if hw_accel in ['any', 'auto', 'automatic', 'dxva2', 'vaapi', 'vdpau', 'videotoolbox', 'd3d11']:
            criteria["hw_accel"]["met"] = True
            criteria["hw_accel"]["feedback"] = f"✅ Hardware acceleration: {hw_accel}"
        else:
            criteria["hw_accel"]["feedback"] = f"❌ Hardware acceleration not enabled (found: {hw_accel})"
        
        # Criterion 2: Frame Skipping
        skip_frames = config.get('skip-frames', '0')
        if skip_frames == '1' or skip_frames == 'true':
            criteria["frame_skip"]["met"] = True
            criteria["frame_skip"]["feedback"] = "✅ Frame skipping enabled"
        else:
            criteria["frame_skip"]["feedback"] = f"❌ Frame skipping disabled (skip-frames={skip_frames})"
        
        # Criterion 3: Lightweight Video Output
        vout = config.get('vout', 'default').lower()
        lightweight_outputs = ['x11', 'xvideo', 'opengl', 'gl']
        if any(lo in vout for lo in lightweight_outputs) or vout == 'any':
            criteria["video_output"]["met"] = True
            criteria["video_output"]["feedback"] = f"✅ Lightweight video output: {vout}"
        elif vout == 'default' or vout == '':
            # Not explicitly set, partial credit
            criteria["video_output"]["feedback"] = "⚠️ Video output not explicitly set (using default)"
        else:
            criteria["video_output"]["feedback"] = f"⚠️ Video output: {vout}"
        
        # Criterion 4: Reduced Caching
        file_caching = config.get('file-caching', '1000')
        try:
            cache_value = int(file_caching)
            if cache_value < 500:
                criteria["cache_reduced"]["met"] = True
                criteria["cache_reduced"]["feedback"] = f"✅ Cache reduced: {cache_value}ms"
            else:
                criteria["cache_reduced"]["feedback"] = f"❌ Cache not reduced: {cache_value}ms (should be <500)"
        except ValueError:
            criteria["cache_reduced"]["feedback"] = f"⚠️ Invalid cache value: {file_caching}"
        
        # Criterion 5: Video Filters Disabled
        video_filter = config.get('video-filter', '')
        if not video_filter or video_filter == '':
            criteria["filters_disabled"]["met"] = True
            criteria["filters_disabled"]["feedback"] = "✅ Video filters disabled"
        else:
            criteria["filters_disabled"]["feedback"] = f"⚠️ Video filters active: {video_filter}"
        
        # Criterion 6: Skip Late Frames
        # Check multiple possible config keys
        skip_late = config.get('skip-late-videoframes', '0')
        skip_late_alt = config.get('skip-late', '0')
        if skip_late == '1' or skip_late_alt == '1':
            criteria["skip_late"]["met"] = True
            criteria["skip_late"]["feedback"] = "✅ Skip late frames enabled"
        else:
            criteria["skip_late"]["feedback"] = "❌ Skip late frames not enabled"
        
        # Criterion 7: Deinterlacing Disabled
        deinterlace = config.get('deinterlace', '0')
        if deinterlace == '0' or deinterlace == '' or deinterlace == 'false':
            criteria["deinterlace_off"]["met"] = True
            criteria["deinterlace_off"]["feedback"] = "✅ Deinterlacing disabled"
        else:
            criteria["deinterlace_off"]["feedback"] = f"⚠️ Deinterlacing enabled: {deinterlace}"
        
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}
    
    # Add all feedback
    for criterion_name, criterion_data in criteria.items():
        feedback_parts.append(criterion_data["feedback"])
    
    # Calculate weighted score
    weighted_score = sum(c["weight"] for c in criteria.values() if c["met"])
    score = int((weighted_score / total_weight) * 100)
    
    # Pass threshold: 70%
    passed = score >= 70
    
    # Count criteria met
    criteria_met = sum(1 for c in criteria.values() if c["met"])
    feedback_parts.insert(1, f"Criteria met: {criteria_met}/7 (weighted score: {score}%)")
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_lowres_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    feedback = " | ".join(feedback_parts)
    
    # Add priority hint if failed
    if not passed and not criteria["hw_accel"]["met"]:
        feedback += " | 💡 TIP: Hardware acceleration is the most important setting!"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }