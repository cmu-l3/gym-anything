#!/usr/bin/env python3
"""
Verifier for Multi-Window Trauma Layout task.
Uses a hybrid approach:
1. Parses the exported text file to ensure at least 3 mathematically distinct W/L settings were logged.
2. Uses a Vision-Language Model on the trajectory frames and final screenshot to confirm the UI is split
   into >=3 panels, displays the same series, and shows distinct contrast differences.
"""

import os
import json
import re
import tempfile
import logging

# Ensure gym_anything VLM utilities can be imported
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a user's performance in Weasis DICOM Viewer. 
The user's goal was to configure a "multi-window trauma layout".
Specifically, they needed to:
1. Split the viewing area into a grid with at least 3 active image panels.
2. Load the *same* anatomical CT series into these panels.
3. Apply distinctly different Window/Level (contrast/brightness) settings to each panel (e.g., one standard soft tissue, one bright for bone, one dark for lung).

Please look at the provided screenshots from the user's session and assess the final visible state:
- multi_panel: Are there at least 3 active image panels visible simultaneously in a grid layout?
- same_series: Does it appear to be the same anatomical image/series duplicated across the panels?
- different_contrast: Do the panels have distinctly different grayscale visual appearances (e.g., contrasting darkness/brightness/clarity of structures)?

Respond strictly in JSON format:
{
    "multi_panel": true/false,
    "same_series": true/false,
    "different_contrast": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_multi_window_trauma_layout(traj, env_info, task_info):
    """Verify the trauma layout configuration task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract and verify text file contents
    text_exists = result.get('text_file_exists', False)
    text_created = result.get('text_file_created_during_task', False)
    text_content = result.get('text_content', '')
    
    if text_exists and text_created:
        score += 10
        feedback_parts.append("Text file created")
        
        # Parse for WC and WW pairs. Using regex to flexibly match "WC 40, WW 400" formats
        # e.g. "WC: 40", "WC=40", "WC -500"
        pattern = r"WC\s*[:=]?\s*(-?\d+\.?\d*).*?WW\s*[:=]?\s*(-?\d+\.?\d*)"
        matches = re.findall(pattern, text_content, re.IGNORECASE)
        
        # Convert to tuples of floats to check uniqueness
        wl_pairs = []
        for wc, ww in matches:
            try:
                wl_pairs.append((float(wc), float(ww)))
            except ValueError:
                pass
                
        unique_pairs = set(wl_pairs)
        
        if len(unique_pairs) >= 3:
            score += 20
            feedback_parts.append(f"Recorded >=3 distinct W/L pairs: {list(unique_pairs)}")
        else:
            feedback_parts.append(f"Recorded only {len(unique_pairs)} distinct W/L pair(s) (expected 3)")
    else:
        feedback_parts.append("W/L text file missing or not created during task")

    # 3. Check for the agent's saved screenshot
    image_exists = result.get('image_file_exists', False)
    image_created = result.get('image_file_created_during_task', False)
    if image_exists and image_created:
        score += 10
        feedback_parts.append("Screenshot saved by agent")
    else:
        feedback_parts.append("Agent screenshot missing")

    # 4. Perform VLM verification using trajectory frames
    if VLM_AVAILABLE:
        try:
            # Sample frames to give context to the VLM (helps confirm progression to the final state)
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
            
            # If the agent saved a screenshot directly, we could also retrieve it, but trajectory 
            # frames are more tamper-resistant and sufficient to prove the visual UI layout.
            if frames:
                vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    
                    if parsed.get("multi_panel", False):
                        score += 20
                        feedback_parts.append("VLM confirmed >=3 panels")
                    else:
                        feedback_parts.append("VLM: Grid layout with >=3 panels not detected")
                        
                    if parsed.get("same_series", False):
                        score += 15
                        feedback_parts.append("VLM confirmed identical series duplicated")
                    else:
                        feedback_parts.append("VLM: Identical series duplication not detected")
                        
                    if parsed.get("different_contrast", False):
                        score += 25
                        feedback_parts.append("VLM confirmed distinct contrasts")
                    else:
                        feedback_parts.append("VLM: Distinct W/L contrasts not detected")
                else:
                    feedback_parts.append("VLM query failed to return valid JSON")
            else:
                feedback_parts.append("No trajectory frames available for VLM")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append(f"VLM Exception: {str(e)[:50]}")
    else:
        # Fallback if VLM isn't strictly loaded
        feedback_parts.append("VLM unavailable - cannot verify visual layout")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }