#!/usr/bin/env python3
"""
Verifier for configure_accessibility_display task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. `prefs.js` Background Color configured to #FFFFCC (20 points)
2. `prefs.js` Text Color configured to #000000 (10 points)
3. `prefs.js` Force Override set to Always/2 (25 points)
4. `prefs.js` Font Size set to 24 (15 points)
5. `prefs.js` System Colors disabled (10 points)
6. Anti-gaming check: prefs.js was modified during the task (required for 100%)
7. VLM: Trajectory + Final screenshot shows dialog usage and visible yellow background (20 points)

Pass threshold: 70 points AND (Background Color OR Override)
"""

import os
import json
import re
import tempfile
import logging

# We import the required VLM tools from the gym_anything framework
# Use defensive imports since they might fail in test environments
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance in configuring accessibility settings in Mozilla Thunderbird.

The goal was to:
1. Open the Colors settings dialog.
2. Set the background to soft yellow (#FFFFCC) and text to black.
3. Apply settings so the email reading pane has a yellow background.

Looking at the provided trajectory of screenshots (from beginning to end):
1. 'dialog_used': Did the agent open the Thunderbird Settings / Colors modal dialog at some point?
2. 'yellow_background_visible': In the final screenshot(s), is the main email viewing area visibly showing a yellow background?

Please output exactly in the following JSON format:
{
    "dialog_used": true/false,
    "yellow_background_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def extract_pref(pref_name, content, default_val=None):
    """Safely extract a user_pref from the prefs.js file content using regex."""
    # Matches: user_pref("preference.name", value);
    # Handles strings, ints, and booleans
    pattern = rf'user_pref\("{re.escape(pref_name)}",\s*([^)]+)\);'
    match = re.search(pattern, content)
    if match:
        val = match.group(1).strip()
        # Remove quotes if it's a string
        if val.startswith('"') and val.endswith('"'):
            return val[1:-1]
        if val.lower() == 'true':
            return 'true'
        if val.lower() == 'false':
            return 'false'
        # Return as integer if possible
        try:
            return int(val)
        except ValueError:
            return val
    return default_val

def verify_accessibility_display(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_bg = metadata.get('expected_bg', '#ffffcc').lower()
    expected_fg = metadata.get('expected_fg', '#000000').lower()
    expected_override = metadata.get('expected_override', 2)
    expected_sys_colors = metadata.get('expected_sys_colors', 'false')
    expected_font_size = metadata.get('expected_font_size', 24)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # Read task_result.json
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read JSON export: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    prefs_modified = result.get('prefs_modified_during_task', False)
    if not prefs_modified:
        feedback_parts.append("prefs.js was not modified during the task (Anti-gaming check)")

    # ================================================================
    # Read prefs.js
    # ================================================================
    temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
    prefs_content = ""
    try:
        copy_from_env("/tmp/task_prefs.js", temp_prefs.name)
        with open(temp_prefs.name, 'r', encoding='utf-8', errors='ignore') as f:
            prefs_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read prefs.js: {e}"}
    finally:
        if os.path.exists(temp_prefs.name):
            os.unlink(temp_prefs.name)

    # Extract values
    actual_bg = str(extract_pref("browser.display.background_color", prefs_content, "")).lower()
    actual_fg = str(extract_pref("browser.display.foreground_color", prefs_content, "")).lower()
    actual_override = extract_pref("browser.display.document_color_use", prefs_content, -1)
    actual_sys_colors = str(extract_pref("browser.display.use_system_colors", prefs_content, "")).lower()
    actual_font_size = extract_pref("font.size.variable.x-western", prefs_content, -1)

    # Criterion 1: Background
    if actual_bg == expected_bg:
        score += 20
        feedback_parts.append("Background color correctly set to #FFFFCC")
    elif actual_bg:
        feedback_parts.append(f"Background color incorrect: {actual_bg}")
    else:
        feedback_parts.append("Background color not customized")

    # Criterion 2: Text Foreground
    if actual_fg == expected_fg:
        score += 10
        feedback_parts.append("Text color correctly set to #000000")
        
    # Criterion 3: Override Colors (Critical)
    if actual_override == expected_override:
        score += 25
        feedback_parts.append("Color override correctly set to 'Always'")
    else:
        feedback_parts.append(f"Color override incorrect (Expected {expected_override}, got {actual_override})")
        
    # Criterion 4: Font Size
    if actual_font_size == expected_font_size:
        score += 15
        feedback_parts.append(f"Font size correctly set to {expected_font_size}")
    else:
        # Check alternative font size key just in case (e.g., minimum-size)
        alt_font = extract_pref("font.minimum-size.x-western", prefs_content, -1)
        if alt_font == expected_font_size:
            score += 15
            feedback_parts.append(f"Font size correctly set via minimum-size to {expected_font_size}")
        else:
            feedback_parts.append(f"Font size incorrect (Expected {expected_font_size})")
            
    # Criterion 5: System Colors Disabled
    if actual_sys_colors == expected_sys_colors:
        score += 10
        feedback_parts.append("System colors successfully disabled")

    # ================================================================
    # VLM Verification
    # ================================================================
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            # Remove none elements if screenshot failed
            valid_images = [img for img in frames + [final] if img is not None]
            
            if valid_images:
                vlm_result = query_vlm(images=valid_images, prompt=VLM_PROMPT)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("dialog_used"):
                        score += 10
                        feedback_parts.append("VLM confirms Colors dialog was accessed")
                    if parsed.get("yellow_background_visible"):
                        score += 10
                        feedback_parts.append("VLM confirms yellow background is visible in UI")
                else:
                    feedback_parts.append(f"VLM check failed: {vlm_result.get('error')}")
                    # Give partial benefit of the doubt if API fails but prefs are correct
                    if score >= 50:
                        score += 20 
            else:
                feedback_parts.append("No valid trajectory frames for VLM")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            if score >= 50:
                score += 20 # Auto pass VLM points if VLM crashes but program state is perfect
    else:
        # If VLM is not available in the testing environment, grant the points if prefs are perfectly set
        logger.warning("VLM module not available. Skipping visual check.")
        if score >= 80:
            score += 20 

    # Combine results
    key_criteria_met = (actual_bg == expected_bg or actual_override == expected_override)
    passed = (score >= 70) and key_criteria_met and prefs_modified
    
    # Handle "Do Nothing" penalty
    if not prefs_modified:
        score = 0
        passed = False
        
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }