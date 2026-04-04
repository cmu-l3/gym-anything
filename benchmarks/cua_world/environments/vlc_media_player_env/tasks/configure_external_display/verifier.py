#!/usr/bin/env python3
"""
Verifier for Configure External Display task
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


def verify_configure_external_display(traj, env_info, task_info):
    """
    Verify configure external display task completion.
    
    Checks:
    1. VLC configuration file is accessible
    2. Display configuration settings are present
    3. Settings point to secondary display (value = 1 or equivalent)
    
    Success requires agent to configure VLC to use secondary display
    for fullscreen playback (simulating projector/external monitor setup).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy display configuration result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_display_result.json", temp_result.name)
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        criteria_met += 1
        feedback_parts.append("✅ Configuration result accessible")
        
        # Check if any display settings were found
        display_settings_found = result.get('display_settings_found', False)
        display_config = result.get('display_config', {})
        
        if not display_settings_found or not display_config:
            os.unlink(temp_result.name)
            return {
                "passed": False,
                "score": 33,
                "feedback": "❌ No display configuration found in VLC preferences. "
                           "You need to set fullscreen display to secondary monitor (screen 1). "
                           "Try: Tools → Preferences → All → Video → Fullscreen Settings"
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ Display settings found: {', '.join(display_config.keys())}")
        
        # Criterion 3: Check if settings point to secondary display
        correct_display_config = False
        display_value_info = []
        
        # Check each setting
        for key, value in display_config.items():
            display_value_info.append(f"{key}={value}")
            
            # Check for correct secondary display configuration
            if key == "qt-fullscreen-screennumber":
                # Most common setting - should be "1" for secondary display
                try:
                    screen_num = int(value)
                    if screen_num == 1:
                        correct_display_config = True
                        feedback_parts.append(f"✅ Correct display configured: {key}={value} (secondary display)")
                    elif screen_num == 0:
                        feedback_parts.append(f"⚠️ Display set to primary (0), should be secondary (1)")
                    else:
                        feedback_parts.append(f"⚠️ Unexpected display value: {value}")
                except (ValueError, TypeError):
                    feedback_parts.append(f"⚠️ Invalid display number: {value}")
            
            elif key == "fullscreen-screen":
                # Alternative setting name
                try:
                    screen_num = int(value)
                    if screen_num == 1:
                        correct_display_config = True
                        feedback_parts.append(f"✅ Correct display configured: {key}={value}")
                    else:
                        feedback_parts.append(f"⚠️ Display value: {value} (expected 1)")
                except (ValueError, TypeError):
                    pass
            
            elif key in ["qt-fullscreen-screenname", "vout-display", "x11-display"]:
                # Check for indicators of secondary display in string values
                value_lower = str(value).lower()
                if any(indicator in value_lower for indicator in [":1.1", "screen=1", "display=1", "monitor=1", "screen 1"]):
                    correct_display_config = True
                    feedback_parts.append(f"✅ Secondary display reference found: {key}={value}")
                else:
                    feedback_parts.append(f"ℹ️ Display setting: {key}={value}")
        
        if correct_display_config:
            criteria_met += 1
        else:
            feedback_parts.append("❌ Display not configured for secondary monitor (expected value: 1)")
        
        os.unlink(temp_result.name)
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading display configuration: {str(e)}"
        }
    
    # Optional: Check completion marker (bonus, not required for pass)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_display_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        if "completed" in marker_content.lower():
            feedback_parts.append("✅ Task completed marker found")
        os.unlink(temp_marker.name)
    except Exception:
        # Marker is optional
        pass
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    # Enhanced feedback for common scenarios
    if not passed:
        if criteria_met == 1:
            feedback += " | 💡 Hint: Open VLC Preferences (Ctrl+P), click 'All', navigate to Video → Fullscreen, set screen number to 1"
        elif criteria_met == 2:
            feedback += " | 💡 Hint: Display setting found but value is incorrect. Set to 1 for secondary display (projector)"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }