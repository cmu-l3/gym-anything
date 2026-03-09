#!/usr/bin/env python3
"""
Verifier for Configure PiP Mode task

Verifies that VLC has been configured in always-on-top picture-in-picture mode
with compact window size and corner positioning.
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


def is_in_corner(x, y, width, height, screen_width, screen_height):
    """
    Check if window is positioned in a screen corner.
    
    Corner regions:
    - Top-right: X > 70% screen width AND Y < 30% screen height
    - Bottom-right: X > 70% screen width AND Y > 70% screen height
    - Top-left: X < 30% screen width AND Y < 30% screen height
    - Bottom-left: X < 30% screen width AND Y > 70% screen height
    
    Args:
        x, y: Window position
        width, height: Window dimensions
        screen_width, screen_height: Screen dimensions
        
    Returns:
        Tuple of (is_in_corner: bool, corner_name: str)
    """
    # Calculate window center for more accurate corner detection
    center_x = x + width / 2
    center_y = y + height / 2
    
    # Define corner thresholds
    left_threshold = screen_width * 0.3
    right_threshold = screen_width * 0.7
    top_threshold = screen_height * 0.3
    bottom_threshold = screen_height * 0.7
    
    # Check corners
    if center_x > right_threshold and center_y < top_threshold:
        return True, "top-right"
    elif center_x > right_threshold and center_y > bottom_threshold:
        return True, "bottom-right"
    elif center_x < left_threshold and center_y < top_threshold:
        return True, "top-left"
    elif center_x < left_threshold and center_y > bottom_threshold:
        return True, "bottom-left"
    
    return False, "center/edge"


def verify_configure_pip_mode(traj, env_info, task_info):
    """
    Verify configure PiP mode task completion.
    
    Checks:
    1. Always-on-top enabled in VLC config (video-on-top=1)
    2. X11 always-on-top property set (_NET_WM_STATE_ABOVE)
    3. Window size is compact (≤500x300 pixels)
    4. Window positioned in corner region
    5. Video playing and remains visible when other windows focused
    
    Pass threshold: 80% (4/5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Copy PiP result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_pip_result.json", temp_result.name)
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        # Extract data
        window_found = result.get('window_found', False)
        window_data = result.get('window_data', {})
        aot_property = result.get('always_on_top_property', False)
        aot_config = result.get('always_on_top_config', False)
        video_playing = result.get('video_playing', False)
        aot_test_passed = result.get('always_on_top_test_passed', False)
        
        if not window_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC window not found - task may not have been attempted"
            }
        
        # Criterion 1: Always-on-top enabled in VLC config
        if aot_config:
            criteria_met += 1
            feedback_parts.append("✅ Always-on-top enabled in VLC config")
        else:
            feedback_parts.append("❌ Always-on-top NOT enabled in VLC config")
        
        # Criterion 2: X11 always-on-top property set
        if aot_property:
            criteria_met += 1
            feedback_parts.append("✅ X11 always-on-top property set")
        else:
            feedback_parts.append("❌ X11 always-on-top property NOT set")
        
        # Criterion 3: Window size is compact (≤500x300 pixels)
        width = window_data.get('width', 0)
        height = window_data.get('height', 0)
        
        if width > 0 and height > 0:
            if width <= 500 and height <= 300:
                criteria_met += 1
                feedback_parts.append(f"✅ Window size compact ({width}x{height}px)")
            else:
                feedback_parts.append(f"❌ Window size too large ({width}x{height}px, max: 500x300px)")
        else:
            feedback_parts.append("❌ Window size not detected")
        
        # Criterion 4: Window positioned in corner region
        x = window_data.get('x', 0)
        y = window_data.get('y', 0)
        screen_width = window_data.get('screen_width', 1920)
        screen_height = window_data.get('screen_height', 1080)
        
        if width > 0 and height > 0:
            in_corner, corner_name = is_in_corner(
                x, y, width, height, screen_width, screen_height
            )
            
            if in_corner:
                criteria_met += 1
                feedback_parts.append(f"✅ Window in {corner_name} corner")
            else:
                # Calculate relative position for feedback
                rel_x = (x / screen_width) * 100
                rel_y = (y / screen_height) * 100
                feedback_parts.append(
                    f"❌ Window not in corner (position: {rel_x:.0f}%, {rel_y:.0f}% from top-left)"
                )
        else:
            feedback_parts.append("❌ Window position not detected")
        
        # Criterion 5: Video playing and always-on-top test passed
        if video_playing or aot_test_passed:
            # Give credit if either video is playing OR always-on-top test passed
            if video_playing and (aot_property or aot_test_passed):
                criteria_met += 1
                feedback_parts.append("✅ Video playing and always-on-top verified")
            elif aot_property:
                criteria_met += 1
                feedback_parts.append("✅ Always-on-top behavior verified")
            else:
                feedback_parts.append("⚠️ Partial: video state uncertain")
        else:
            feedback_parts.append("❌ Video not playing or always-on-top not verified")
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading PiP result: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_pip_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80  # Need 4/5 criteria
    
    # Build detailed feedback
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    summary = f"Criteria met: {criteria_met}/{total_criteria}"
    if passed:
        summary += " ✅ PASSED"
    else:
        summary += " ❌ FAILED"
    
    full_feedback = f"{summary} | {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": full_feedback,
        "criteria_met": criteria_met,
        "total_criteria": total_criteria,
        "details": {
            "always_on_top_config": aot_config,
            "always_on_top_property": aot_property,
            "window_size": f"{width}x{height}",
            "window_position": f"({x}, {y})",
            "screen_size": f"{screen_width}x{screen_height}"
        }
    }