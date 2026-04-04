#!/usr/bin/env python3
"""
Verifier for Pin Tutorial Window task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_pin_tutorial_window(traj, env_info, task_info):
    """
    Verify pin tutorial window task completion.
    
    Checks:
    1. Window configuration file exists and is valid
    2. Window dimensions are compact (500-700 x 300-450)
    3. Window is positioned in top-right area
    4. Always-on-top is enabled
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Copy window configuration JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_window_config.json", temp_result.name)
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            config = json.load(f)
        
        criteria_met += 1
        feedback_parts.append("✅ Window configuration accessible")
        
        # Get window properties
        x = config.get('x', 0)
        y = config.get('y', 0)
        width = config.get('width', 0)
        height = config.get('height', 0)
        screen_width = config.get('screen_width', 1920)
        screen_height = config.get('screen_height', 1080)
        always_on_top = config.get('always_on_top', False)
        
        feedback_parts.append(f"Window: {width}x{height} at ({x},{y})")
        feedback_parts.append(f"Screen: {screen_width}x{screen_height}")
        
        # Criterion 2: Check window dimensions (compact size)
        # Target: 640x360, acceptable range: 500-700 x 300-450
        if 500 <= width <= 700 and 300 <= height <= 450:
            criteria_met += 1
            feedback_parts.append(f"✅ Window size compact ({width}x{height})")
        else:
            # Give partial credit if at least one dimension is in range
            width_ok = 500 <= width <= 700
            height_ok = 300 <= height <= 450
            
            if width_ok or height_ok:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Window size partially correct ({width}x{height}, target ~640x360)")
            else:
                feedback_parts.append(f"❌ Window size not compact (expected 500-700 x 300-450, got {width}x{height})")
        
        # Criterion 3: Check window position (top-right area)
        # Window should be:
        # - In right half of screen (x > 50% of screen width)
        # - Near top (y < 100 pixels, accounting for window decorations)
        
        right_threshold = screen_width * 0.5
        in_right_half = x > right_threshold
        
        # Allow some margin for window decorations/title bar
        near_top = y < 100
        
        position_score = 0
        if in_right_half and near_top:
            position_score = 1.0
            feedback_parts.append(f"✅ Window in top-right (x={x} > {right_threshold:.0f}, y={y} < 100)")
        elif in_right_half:
            position_score = 0.5
            feedback_parts.append(f"⚠️ Window in right area but not at top (x={x}, y={y})")
        elif near_top:
            position_score = 0.5
            feedback_parts.append(f"⚠️ Window at top but not in right area (x={x} <= {right_threshold:.0f})")
        else:
            position_score = 0
            feedback_parts.append(f"❌ Window not in top-right area (x={x}, y={y})")
        
        criteria_met += position_score
        
        # Criterion 4: Check always-on-top
        if always_on_top:
            criteria_met += 1
            feedback_parts.append("✅ Always-on-top enabled")
        else:
            feedback_parts.append("❌ Always-on-top not enabled")
        
        os.unlink(temp_result.name)
        
    except FileNotFoundError:
        logger.error("Window configuration file not found")
        return {"passed": False, "score": 0, "feedback": "Window configuration file not found"}
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in configuration file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Invalid window configuration: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading window configuration: {str(e)}"}
    
    # Check completion marker (optional, doesn't affect score)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_tutorial_window_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            content = f.read()
        if content:
            feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        # Completion marker is not critical
        pass
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }