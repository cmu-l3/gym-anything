#!/usr/bin/env python3
"""
Verifier for Enable HDR Tone Mapping task
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


def verify_hdr_tone_mapping(traj, env_info, task_info):
    """
    Verify HDR tone mapping task completion.
    
    Checks:
    1. VLC config file is accessible and parseable
    2. Tone mapping or video filters are enabled
    3. Configuration indicates HDR tone mapping is active
    
    VLC tone mapping settings:
    - video-filter or vout-filter should contain "tonemapping" or "adjust"
    - tone-mapping-mode may be set
    - Alternative: adjust filter with specific parameters
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy VLC config file
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        try:
            copy_from_env("/tmp/vlc_hdr_config.txt", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying VLC config: {e}", exc_info=True)
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"❌ Could not access VLC config: {str(e)}"
            }
        
        # Check if file exists and has content
        if not os.path.exists(temp_config.name) or os.path.getsize(temp_config.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC config file is empty or missing"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")
        
        # Parse VLC configuration
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            logger.warning("Config parsing returned empty dict")
            # Still try to read raw file
            with open(temp_config.name, 'r') as f:
                raw_config = f.read()
        else:
            raw_config = ""
        
        logger.info(f"Parsed config keys: {list(config.keys())}")
        
        # Criterion 2: Check for tone mapping or video filter settings
        tone_mapping_found = False
        filter_enabled = False
        tone_mapping_details = []
        
        # Method 1: Check video-filter or vout-filter for tone mapping
        video_filter = config.get('video-filter', '').lower()
        vout_filter = config.get('vout-filter', '').lower()
        
        logger.info(f"video-filter: '{video_filter}'")
        logger.info(f"vout-filter: '{vout_filter}'")
        
        # Check for tone mapping keywords
        tone_mapping_keywords = ['tonemapping', 'tone-mapping', 'tonemap', 'hdr']
        adjust_keywords = ['adjust', 'adjustment']
        
        for keyword in tone_mapping_keywords:
            if keyword in video_filter or keyword in vout_filter:
                tone_mapping_found = True
                filter_enabled = True
                tone_mapping_details.append(f"tone mapping in video filters")
                break
        
        # Alternative: Image adjust filter can be used for tone mapping
        if not tone_mapping_found:
            for keyword in adjust_keywords:
                if keyword in video_filter or keyword in vout_filter:
                    filter_enabled = True
                    tone_mapping_details.append(f"adjust filter enabled (can handle HDR)")
                    # This is partial credit - adjust filter is not as good as dedicated tone mapping
                    break
        
        # Method 2: Check for specific tone mapping parameters
        tone_mapping_mode = config.get('tone-mapping-mode', config.get('tonemapping-mode', ''))
        tone_mapping_param = config.get('tone-mapping-param', '')
        
        if tone_mapping_mode and tone_mapping_mode != '0':
            tone_mapping_found = True
            tone_mapping_details.append(f"tone mapping mode: {tone_mapping_mode}")
        
        if tone_mapping_param:
            tone_mapping_details.append(f"tone mapping params configured")
        
        # Method 3: Raw text search in config (backup)
        if not tone_mapping_found and not filter_enabled:
            if raw_config:
                if re.search(r'tone-?map', raw_config, re.IGNORECASE):
                    tone_mapping_found = True
                    tone_mapping_details.append("tone mapping detected in config")
                elif re.search(r'adjust.*=.*[^0]', raw_config, re.IGNORECASE):
                    filter_enabled = True
                    tone_mapping_details.append("adjust filter detected")
        
        # Scoring logic
        if tone_mapping_found:
            criteria_met += 2  # Full credit for tone mapping
            feedback_parts.append(f"✅ Tone mapping filter enabled: {', '.join(tone_mapping_details)}")
        elif filter_enabled:
            criteria_met += 1  # Partial credit for adjust filter
            feedback_parts.append(f"⚠️ Video filter enabled but tone mapping unclear: {', '.join(tone_mapping_details)}")
        else:
            feedback_parts.append("❌ Tone mapping filter not enabled")
            logger.warning("No tone mapping indicators found in config")
        
        # Criterion 3: Check that settings are valid and persistent
        # Config file should have substantial content (not just defaults)
        config_size = os.path.getsize(temp_config.name)
        
        if config_size > 100:
            # Check that either tone mapping or video filter was modified from default
            if tone_mapping_found or filter_enabled:
                criteria_met += 0  # Already counted above
                feedback_parts.append("✅ Settings saved to config")
            else:
                feedback_parts.append("⚠️ Config exists but tone mapping not configured")
        else:
            feedback_parts.append("⚠️ Config file may not have been saved properly")
        
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    # Check completion marker (bonus, not required for scoring)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_hdr_completed.txt", temp_marker.name)
        logger.info("✅ Completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        logger.info("⚠️ Completion marker not found (non-critical)")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build final feedback
    if passed:
        status_icon = "✅"
        status_text = "SUCCESS"
    else:
        status_icon = "❌"
        status_text = "INCOMPLETE"
    
    feedback = f"{status_icon} {status_text} | " + " | ".join(feedback_parts)
    
    # Add helpful hint if failed
    if not passed:
        feedback += " | 💡 Hint: Navigate to Tools → Preferences → All → Video → Filters and enable 'Tone mapping'"
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    logger.info(f"Feedback: {feedback}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }