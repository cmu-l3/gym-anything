#!/usr/bin/env python3
"""
Verifier for Customize Subtitle Appearance task.
Checks that VLC subtitle appearance settings have been properly configured.
"""

import sys
import os
import logging
import tempfile
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_customize_subtitle_appearance(traj, env_info, task_info):
    """
    Verify subtitle appearance customization.
    
    Checks:
    1. Font size increased from default (≥30, default ~20)
    2. Background opacity enabled (≥128, range 0-255)
    3. Background color is dark (for contrast)
    
    Returns:
        dict with keys: passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5  # Multiple sub-criteria with partial credit
    feedback_parts = []
    
    # Copy VLC config
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_subtitle_appearance_config.txt", temp_config.name)
    except Exception as e:
        logger.error(f"Error copying config: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ VLC config file not found. Did you save preferences? Error: {str(e)}"
        }
    
    # Parse VLC config
    try:
        config = parse_vlc_config(temp_config.name)
    except Exception as e:
        logger.error(f"Error parsing config: {e}", exc_info=True)
        os.unlink(temp_config.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Could not parse VLC config: {str(e)}"
        }
    
    if not config:
        os.unlink(temp_config.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ VLC config is empty. Did you save preferences?"
        }
    
    details = {}
    
    # Criterion 1: Font size (should be increased from default ~20)
    font_size = None
    if 'freetype-fontsize' in config:
        try:
            font_size = int(config['freetype-fontsize'])
            details['font_size'] = font_size
        except (ValueError, TypeError):
            logger.warning(f"Could not parse font size: {config['freetype-fontsize']}")
    
    # Also check relative font size as alternative
    rel_font_size = config.get('freetype-rel-fontsize', None)
    if rel_font_size:
        details['rel_font_size'] = rel_font_size
    
    if font_size and font_size >= 30:
        feedback_parts.append(f"✅ Font size increased to {font_size} pixels (excellent readability)")
        criteria_met += 2  # Double weight for main criterion
    elif font_size and font_size >= 24:
        feedback_parts.append(f"⚠️ Font size is {font_size} pixels (moderately increased, but target was ≥30)")
        criteria_met += 1  # Partial credit
    elif font_size and font_size > 20:
        feedback_parts.append(f"⚠️ Font size is {font_size} pixels (slightly increased from default)")
        criteria_met += 0.5  # Minimal credit
    elif font_size:
        feedback_parts.append(f"❌ Font size is {font_size} pixels (should be ≥30 for large screen viewing)")
    else:
        feedback_parts.append("❌ Font size setting not found or not modified")
    
    # Criterion 2: Background opacity (should be enabled with reasonable opacity)
    bg_opacity = None
    if 'freetype-background-opacity' in config:
        try:
            bg_opacity = int(config['freetype-background-opacity'])
            details['background_opacity'] = bg_opacity
        except (ValueError, TypeError):
            logger.warning(f"Could not parse background opacity: {config['freetype-background-opacity']}")
    
    if bg_opacity and bg_opacity >= 128:
        feedback_parts.append(f"✅ Background opacity set to {bg_opacity}/255 (good contrast)")
        criteria_met += 2  # Double weight
    elif bg_opacity and bg_opacity >= 64:
        feedback_parts.append(f"⚠️ Background opacity is {bg_opacity}/255 (enabled but somewhat transparent)")
        criteria_met += 1  # Partial credit
    elif bg_opacity and bg_opacity > 0:
        feedback_parts.append(f"⚠️ Background opacity is {bg_opacity}/255 (very transparent, may not help much)")
        criteria_met += 0.5  # Minimal credit
    elif bg_opacity == 0:
        feedback_parts.append("❌ Background opacity is 0 (background disabled, no contrast)")
    else:
        feedback_parts.append("❌ Background opacity setting not found")
    
    # Criterion 3: Background color (should be dark for contrast with white text)
    bg_color = config.get('freetype-background-color', None)
    if bg_color:
        details['background_color'] = bg_color
        try:
            # VLC stores color as signed integer, may be negative
            color_val = int(bg_color)
            if color_val < 0:
                # Convert negative to unsigned 24-bit RGB
                color_val = color_val & 0xFFFFFF
            
            # Extract RGB components
            r = (color_val >> 16) & 0xFF
            g = (color_val >> 8) & 0xFF
            b = color_val & 0xFF
            
            brightness = (r + g + b) / 3
            details['background_brightness'] = brightness
            
            if brightness < 50:
                feedback_parts.append(f"✅ Background color is dark (brightness: {brightness:.0f}/255)")
                criteria_met += 1
            elif brightness < 128:
                feedback_parts.append(f"⚠️ Background color is somewhat dark (brightness: {brightness:.0f}/255)")
                criteria_met += 0.5
            else:
                feedback_parts.append(f"❌ Background color is too bright (brightness: {brightness:.0f}/255)")
        except (ValueError, TypeError) as e:
            logger.warning(f"Could not parse background color: {bg_color}, error: {e}")
            feedback_parts.append("⚠️ Background color set but couldn't verify darkness")
            criteria_met += 0.3
    
    # Alternative contrast method: Check for outline/shadow settings
    outline_thickness = config.get('freetype-outline-thickness', None)
    if outline_thickness:
        try:
            thickness = int(outline_thickness)
            if thickness > 0:
                details['outline_thickness'] = thickness
                feedback_parts.append(f"✅ Alternative contrast method: Text outline enabled (thickness: {thickness})")
                # If they used outline instead of background, give some credit
                if not bg_opacity or bg_opacity < 64:
                    criteria_met += 1
        except (ValueError, TypeError):
            pass
    
    # Clean up temp file
    os.unlink(temp_config.name)
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_subtitle_appearance_completed.txt", temp_marker.name)
        logger.info("Task completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        logger.warning("Completion marker not found")
        feedback_parts.append("⚠️ Note: Completion marker not found")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    # Cap at 100
    score = min(score, 100)
    
    passed = score >= 70  # Need at least 70% of criteria met
    
    feedback = "\n".join(feedback_parts)
    
    if passed:
        feedback = "🎉 Subtitle appearance successfully customized for readability!\n\n" + feedback
    else:
        feedback = "❌ Subtitle appearance configuration incomplete.\n\n" + feedback
        feedback += "\n\n💡 Tip: Open Tools → Preferences → Show All Settings (bottom left)"
        feedback += "\n   Navigate to: Video → Subtitles/OSD → Text renderer"
        feedback += "\n   Configure: Font size (≥30), Background opacity (≥128), Background color (dark)"
    
    logger.info(f"Verification result: success={passed}, score={score}")
    logger.info(f"Details: {details}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
