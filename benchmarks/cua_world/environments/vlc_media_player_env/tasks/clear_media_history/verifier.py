#!/usr/bin/env python3
"""
Verifier for Clear Media History task
"""

import sys
import os
import logging
import tempfile
import json
import configparser
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_qt_interface_config(config_path):
    """
    Parse VLC Qt interface config to extract recent items.
    
    Args:
        config_path: Path to vlc-qt-interface.conf
        
    Returns:
        List of recent media file paths
    """
    recent_items = []
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Look for file:// URLs which indicate recent media
        import re
        file_urls = re.findall(r'file://[^\s,\]]+', content)
        recent_items = file_urls
        
        logger.info(f"Found {len(recent_items)} recent items in config")
        
    except Exception as e:
        logger.error(f"Error parsing Qt interface config: {e}")
    
    return recent_items


def verify_clear_media_history(traj, env_info, task_info):
    """
    Verify clear media history task completion.
    
    Checks:
    1. Recent items count is zero or minimal (≤1)
    2. Config was modified during task (count reduced)
    3. Config file is accessible and parseable
    
    Scoring:
    - 100%: All criteria met (perfect clearing)
    - 85%: Recent items cleared but may not have saved properly
    - 70%: Partial clearing or some items remain
    - <70%: Clearing failed
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy history result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_history_result.json", temp_result.name)
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        criteria_met += 1
        feedback_parts.append("✅ History result accessible")
        
        # Get metrics from result
        recent_count = result.get('recent_items_count', 999)
        config_modified = result.get('config_modified', False)
        config_exists = result.get('config_file_exists', False)
        initial_count = result.get('initial_count', 0)
        
        feedback_parts.append(f"Initial: {initial_count} items, Final: {recent_count} items")
        
        # Criterion 1: Recent items count is zero or minimal
        if recent_count == 0:
            criteria_met += 1
            feedback_parts.append("✅ Recent history completely cleared")
        elif recent_count <= 1:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Recent history mostly cleared ({recent_count} item remains)")
        else:
            feedback_parts.append(f"❌ Recent history not cleared ({recent_count} items remain)")
        
        # Criterion 2: Config was modified (clearing action taken)
        if config_modified:
            criteria_met += 1
            feedback_parts.append("✅ Configuration was modified")
        else:
            # Check if initial count was already 0 (edge case)
            if initial_count == 0:
                criteria_met += 0.5
                feedback_parts.append("⚠️ History was already empty")
            else:
                feedback_parts.append("❌ Configuration not modified")
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading history result: {str(e)}"}
    
    # Additional verification: Parse config file directly
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    try:
        copy_from_env("/tmp/vlc_qt_interface_export.conf", temp_config.name)
        
        # Parse config to double-check recent items
        recent_items = parse_qt_interface_config(temp_config.name)
        
        if len(recent_items) == 0:
            feedback_parts.append("✅ Config verification: No recent items found")
        elif len(recent_items) <= 2:
            feedback_parts.append(f"⚠️ Config verification: {len(recent_items)} items found")
        else:
            feedback_parts.append(f"❌ Config verification: {len(recent_items)} items found")
        
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.warning(f"Could not verify config directly: {e}")
        feedback_parts.append("⚠️ Direct config verification unavailable")
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_history_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    # Normalize criteria_met to be out of total_criteria
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }