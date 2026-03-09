#!/usr/bin/env python3
"""
Verifier for Colorblind Accessibility Configuration task

Checks:
1. Colorblind theme extension installed (15 points)
2. Theme activated (10 points)
3. Terminal colors customized (25 points)
4. Git diff colors customized (25 points)
5. Error indicator customization (15 points)
6. Configuration persistence (10 points)

Pass threshold: 70 points
"""

import sys
import os
import json
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def is_hex_color(value):
    """Check if value is a hex color string"""
    if not isinstance(value, str):
        return False
    # Match #RGB, #RRGGBB, #RRGGBBAA formats
    return bool(re.match(r'^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$', value))


def hex_to_rgb(hex_color):
    """Convert hex color to RGB tuple"""
    hex_color = hex_color.lstrip('#')
    if len(hex_color) == 3:
        hex_color = ''.join([c*2 for c in hex_color])
    elif len(hex_color) == 8:
        hex_color = hex_color[:6]  # Strip alpha
    
    if len(hex_color) != 6:
        return None
    
    try:
        r = int(hex_color[0:2], 16)
        g = int(hex_color[2:4], 16)
        b = int(hex_color[4:6], 16)
        return (r, g, b)
    except:
        return None


def is_colorblind_safe(color_hex):
    """
    Check if color avoids problematic red/green hues for deuteranopia
    
    Returns True if the color is safe (not pure red or pure green)
    """
    if not color_hex:
        return False
    
    rgb = hex_to_rgb(color_hex)
    if rgb is None:
        return False
    
    r, g, b = rgb
    
    # Pure red range: high red, low green, low blue
    # Consider #FF0000 to #FF6666 and similar as problematic
    if r > 200 and g < 100 and b < 100:
        logger.debug(f"Color {color_hex} rejected: too red (r={r}, g={g}, b={b})")
        return False
    
    # Pure green range: low red, high green, low blue
    # Consider #00FF00 to #66FF66 as problematic
    if r < 100 and g > 200 and b < 100:
        logger.debug(f"Color {color_hex} rejected: too green (r={r}, g={g}, b={b})")
        return False
    
    return True


def check_accessible_theme_keyword(text):
    """Check if text contains accessibility-related keywords"""
    if not text:
        return False
    
    text_lower = text.lower()
    keywords = [
        'colorblind', 'colour-blind', 'color-blind',
        'a11y', 'accessible', 'accessibility',
        'blinds', 'daltonize', 'deuteranopia', 'protanopia',
        'tritanopia', 'cvd'  # Color Vision Deficiency
    ]
    
    return any(keyword in text_lower for keyword in keywords)


def verify_colorblind_accessibility(traj, env_info, task_info):
    """
    Verify colorblind accessibility configuration
    
    Returns:
        dict: {passed: bool, score: int, feedback: str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='colorblind_verify_')
    
    try:
        score = 0
        max_score = 100
        feedback_parts = []
        
        # Copy settings.json
        settings_local = os.path.join(temp_dir, "settings.json")
        try:
            copy_from_env("/tmp/vscode_settings.json", settings_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to copy settings.json: {str(e)}"
            }
        
        # Parse settings
        try:
            with open(settings_local, 'r', encoding='utf-8') as f:
                settings = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to parse settings.json: {str(e)}"
            }
        
        # Criterion 1: Check for colorblind theme extension (15 points)
        extensions_ids_local = os.path.join(temp_dir, "extensions_ids.txt")
        extensions_dirs_local = os.path.join(temp_dir, "extensions_dirs.txt")
        
        accessible_extension_found = False
        try:
            copy_from_env("/tmp/vscode_extensions_ids.txt", extensions_ids_local)
            if os.path.exists(extensions_ids_local):
                with open(extensions_ids_local, 'r') as f:
                    extensions_content = f.read()
                    if check_accessible_theme_keyword(extensions_content):
                        accessible_extension_found = True
                        score += 15
                        feedback_parts.append("✅ Colorblind-friendly extension installed")
        except:
            pass
        
        if not accessible_extension_found:
            try:
                copy_from_env("/tmp/vscode_extensions_dirs.txt", extensions_dirs_local)
                if os.path.exists(extensions_dirs_local):
                    with open(extensions_dirs_local, 'r') as f:
                        extensions_content = f.read()
                        if check_accessible_theme_keyword(extensions_content):
                            accessible_extension_found = True
                            score += 15
                            feedback_parts.append("✅ Colorblind-friendly extension installed")
            except:
                pass
        
        if not accessible_extension_found:
            feedback_parts.append("⚠️ No colorblind extension detected (optional)")
        
        # Criterion 2: Check theme activation (10 points)
        theme = settings.get('workbench.colorTheme', '')
        color_custom = settings.get('workbench.colorCustomizations', {})
        
        if check_accessible_theme_keyword(theme) or len(color_custom) > 0:
            score += 10
            if check_accessible_theme_keyword(theme):
                feedback_parts.append(f"✅ Accessible theme activated: {theme}")
            else:
                feedback_parts.append("✅ Custom color overrides present")
        else:
            feedback_parts.append("❌ No accessible theme or custom colors configured")
        
        # Criterion 3: Check terminal colors customization (25 points)
        terminal_colors = {
            k: v for k, v in color_custom.items() 
            if k.startswith('terminal.ansi') and is_hex_color(v)
        }
        
        safe_terminal_colors = 0
        for color_key, color_value in terminal_colors.items():
            if is_colorblind_safe(color_value):
                safe_terminal_colors += 1
                logger.debug(f"Terminal color {color_key} = {color_value} is safe")
        
        # Award up to 25 points: 8 points per safe color (up to 3)
        terminal_score = min(25, safe_terminal_colors * 8)
        score += terminal_score
        
        if safe_terminal_colors > 0:
            feedback_parts.append(
                f"✅ Terminal colors customized: {safe_terminal_colors} safe colors "
                f"({terminal_score}/25 points)"
            )
        else:
            if terminal_colors:
                feedback_parts.append(
                    f"⚠️ Terminal colors modified but using unsafe red/green hues"
                )
            else:
                feedback_parts.append("❌ Terminal colors not customized")
        
        # Criterion 4: Check git diff colors (25 points)
        diff_insert = color_custom.get('diffEditor.insertedTextBackground', '')
        diff_remove = color_custom.get('diffEditor.removedTextBackground', '')
        
        diff_score = 0
        if diff_insert and is_hex_color(diff_insert):
            if is_colorblind_safe(diff_insert):
                diff_score += 12.5
                feedback_parts.append(
                    f"✅ Git diff insertion color configured: {diff_insert}"
                )
            else:
                feedback_parts.append(
                    f"⚠️ Git diff insertion color uses unsafe hue: {diff_insert}"
                )
        else:
            feedback_parts.append("❌ Git diff insertion color not configured")
        
        if diff_remove and is_hex_color(diff_remove):
            if is_colorblind_safe(diff_remove):
                diff_score += 12.5
                feedback_parts.append(
                    f"✅ Git diff removal color configured: {diff_remove}"
                )
            else:
                feedback_parts.append(
                    f"⚠️ Git diff removal color uses unsafe hue: {diff_remove}"
                )
        else:
            feedback_parts.append("❌ Git diff removal color not configured")
        
        score += int(diff_score)
        
        # Criterion 5: Check error indicator customization (15 points)
        error_fg = color_custom.get('editorError.foreground', '')
        error_border = color_custom.get('editorError.border', '')
        warning_fg = color_custom.get('editorWarning.foreground', '')
        line_highlight = settings.get('editor.renderLineHighlight', '')
        
        error_customized = False
        if error_fg and is_hex_color(error_fg) and is_colorblind_safe(error_fg):
            error_customized = True
            feedback_parts.append(f"✅ Error foreground color customized: {error_fg}")
        
        if error_border and is_hex_color(error_border) and is_colorblind_safe(error_border):
            error_customized = True
            feedback_parts.append(f"✅ Error border color customized: {error_border}")
        
        if warning_fg and is_hex_color(warning_fg):
            feedback_parts.append(f"✅ Warning color customized: {warning_fg}")
        
        if line_highlight:
            feedback_parts.append(f"✅ Line highlighting enabled: {line_highlight}")
        
        if error_customized or line_highlight:
            score += 15
        else:
            feedback_parts.append("❌ Error indicators not customized")
        
        # Criterion 6: Configuration persistence (10 points)
        if os.path.exists(settings_local) and os.path.getsize(settings_local) > 50:
            score += 10
            feedback_parts.append("✅ Configuration saved persistently")
        else:
            feedback_parts.append("❌ Configuration not saved")
        
        # Calculate final results
        percentage = (score / max_score) * 100
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "max_score": max_score,
            "percentage": round(percentage, 1),
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp(temp_dir)
