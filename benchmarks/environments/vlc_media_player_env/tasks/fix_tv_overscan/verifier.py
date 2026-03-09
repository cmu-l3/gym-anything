#!/usr/bin/env python3
"""
Verifier for Fix TV Overscan task

Verifies that VLC is configured to add padding/margins around video
to compensate for TV overscan.
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


def parse_vlc_config_file(config_path):
    """
    Parse VLC config file and extract relevant settings.
    
    Returns dict with filter settings and parameters.
    """
    config = {}
    
    try:
        with open(config_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                
                # Skip comments and empty lines
                if not line or line.startswith('#') or line.startswith('['):
                    continue
                
                # Parse key=value
                if '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
    
    except Exception as e:
        logger.error(f"Error parsing VLC config: {e}")
    
    return config


def check_canvas_filter_enabled(config):
    """
    Check if canvas or padding filter is enabled in VLC config.
    
    Returns (enabled, filter_name, details)
    """
    video_filter = config.get('video-filter', '')
    vout_filter = config.get('vout-filter', '')
    
    # Check for canvas, padding, or transform filters
    filter_keywords = ['canvas', 'pad', 'transform']
    
    enabled = False
    filter_name = None
    
    for keyword in filter_keywords:
        if keyword in video_filter.lower():
            enabled = True
            filter_name = keyword
            break
        if keyword in vout_filter.lower():
            enabled = True
            filter_name = keyword
            break
    
    return enabled, filter_name


def check_padding_configured(config):
    """
    Check if padding/canvas parameters are configured.
    
    Returns (configured, params_dict)
    """
    padding_keys = [
        'canvas-width', 'canvas-height', 'canvas-aspect',
        'canvas-padd', 'canvas-padding',
        'transform-type', 'padding-left', 'padding-right',
        'padding-top', 'padding-bottom'
    ]
    
    found_params = {}
    
    for key in padding_keys:
        if key in config:
            found_params[key] = config[key]
    
    configured = len(found_params) > 0
    
    return configured, found_params


def verify_overscan_fix(traj, env_info, task_info):
    """
    Verify fix TV overscan task completion.
    
    Checks:
    1. VLC config file is accessible
    2. Canvas/padding video filter is enabled
    3. Padding parameters are configured
    
    The key verification is that some form of canvas/padding filter
    is enabled with appropriate parameters in VLC's config file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy VLC config file from container
    temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        # Try to copy the vlcrc file directly
        try:
            copy_from_env('/home/ga/.config/vlc/vlcrc', temp_vlcrc.name)
        except Exception as e:
            logger.error(f"Failed to copy vlcrc directly: {e}")
            # Try copying the exported version
            try:
                copy_from_env('/tmp/vlc_overscan_vlcrc.txt', temp_vlcrc.name)
            except Exception as e2:
                logger.error(f"Failed to copy exported vlcrc: {e2}")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"Cannot access VLC config file: {str(e)}"
                }
        
        # Criterion 1: Config file accessible
        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")
        
        # Parse config file
        config = parse_vlc_config_file(temp_vlcrc.name)
        
        if not config:
            return {
                "passed": False,
                "score": 33,
                "feedback": "VLC config file is empty or unreadable"
            }
        
        logger.info(f"Parsed {len(config)} config entries")
        
        # Criterion 2: Check if canvas/padding filter is enabled
        filter_enabled, filter_name = check_canvas_filter_enabled(config)
        
        if filter_enabled:
            criteria_met += 1
            feedback_parts.append(f"✅ Canvas/padding filter enabled ({filter_name})")
        else:
            feedback_parts.append("❌ No canvas/padding filter enabled in video-filter or vout-filter")
            logger.warning("No filter found. video-filter: %s, vout-filter: %s",
                         config.get('video-filter', 'none'),
                         config.get('vout-filter', 'none'))
        
        # Criterion 3: Check if padding parameters are configured
        padding_configured, padding_params = check_padding_configured(config)
        
        if padding_configured:
            criteria_met += 1
            param_summary = ', '.join([f"{k}={v}" for k, v in list(padding_params.items())[:3]])
            feedback_parts.append(f"✅ Padding parameters configured ({param_summary})")
        else:
            # Partial credit if filter is enabled but no explicit params
            # (some filters might work with defaults)
            if filter_enabled:
                criteria_met += 0.5
                feedback_parts.append("⚠️ Filter enabled but no explicit padding parameters found")
            else:
                feedback_parts.append("❌ No padding parameters configured")
        
        os.unlink(temp_vlcrc.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    # Also check the JSON result file for additional info
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vlc_overscan_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        filter_enabled_export = result.get('filter_enabled', False)
        filter_name_export = result.get('filter_name', '')
        
        if filter_enabled_export and filter_name_export:
            logger.info(f"Export confirms filter enabled: {filter_name_export}")
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.warning(f"Could not read result JSON (non-critical): {e}")
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_overscan_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Verification result: {criteria_met}/{total_criteria} criteria met, score={score}, passed={passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }