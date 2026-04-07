#!/usr/bin/env python3
"""
Verifier for urban_light_pollution_advocacy task.

Scoring (100 points):
- Location configured to New York (lat within 0.1 rad of 40.71°N): 15 pts
- Display Overlays (Atmosphere ON, Constellation lines ON): 20 pts
- Artifact Creation (2+ screenshots): 15 pts
- Presentation Notes (contains keywords): 20 pts
- VLM Visual Verification (Agent manipulated light pollution and contrast visible): 30 pts

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    GYM_VLM_AVAILABLE = True
except ImportError:
    GYM_VLM_AVAILABLE = False

logger = logging.getLogger(__name__)

# New York ground truth
NY_LAT_RAD = 0.7105    # ~40.71 degrees N
NY_LON_RAD = -1.2916   # ~-74.00 degrees W
LAT_LON_TOLERANCE_RAD = 0.10


VLM_PROMPT = """You are evaluating a sequence of screenshots from an agent completing a light pollution advocacy task in Stellarium.
The agent was asked to simulate severe urban light pollution (Bortle 8) and a pristine dark sky (Bortle 1), taking screenshots of each.

Please analyze the provided frames and determine:
1. Did the agent open the Sky and Viewing options dialog (F4)?
2. Is there evidence that the agent manipulated the Light Pollution setting (e.g., unchecked "Use light pollution from locations database" or altered the Bortle scale value)?
3. Between the frames, is there a clear visual contrast in sky glow/star density, indicating they successfully simulated both a highly polluted sky and a very dark sky?

Respond in JSON format:
{
    "manipulated_light_pollution": true/false,
    "visible_contrast": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_urban_light_pollution_advocacy(traj, env_info, task_info):
    """Verify urban light pollution advocacy task."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "urban_light_pollution_advocacy"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name

        try:
            copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # ── Criterion 1: Location near New York (15 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - NY_LAT_RAD)
            lon_diff = abs(lon_rad - NY_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 15
                subscores["location"] = True
                feedback_parts.append(
                    f"New York location set (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~40.71°N, ~-74.00°W)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Display Overlays (20 pts) ─────────────
        flag_atm = result.get('flag_atmosphere')
        flag_lines = result.get('flag_constellation_drawing')
        
        if flag_atm is True:
            score += 10
            feedback_parts.append("Atmosphere enabled")
            subscores["atmosphere"] = True
        else:
            feedback_parts.append("Atmosphere disabled (should be ON for light pollution)")
            subscores["atmosphere"] = False
            
        if flag_lines is True:
            score += 10
            feedback_parts.append("Constellation lines enabled")
            subscores["constellation_lines"] = True
        else:
            feedback_parts.append("Constellation lines disabled")
            subscores["constellation_lines"] = False

        # ── Criterion 3: 2+ screenshots taken (15 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 2:
            score += 15
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} screenshots captured")
        elif new_ss == 1:
            score += 7
            subscores["screenshots"] = False
            feedback_parts.append("Only 1 screenshot captured (partial)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots captured")

        # ── Criterion 4: Presentation Notes (20 pts) ─────────────────────────
        notes_exists = result.get('notes_exists', False)
        if notes_exists:
            kw_score = 0
            if result.get('notes_has_new_york'): kw_score += 1
            if result.get('notes_has_orion'): kw_score += 1
            if result.get('notes_has_bortle'): kw_score += 1
            
            if kw_score == 3:
                score += 20
                subscores["notes"] = True
                feedback_parts.append("Presentation notes written with all keywords")
            elif kw_score > 0:
                score += 10
                subscores["notes"] = False
                feedback_parts.append(f"Presentation notes missing some keywords ({kw_score}/3 found)")
            else:
                score += 5
                subscores["notes"] = False
                feedback_parts.append("Presentation notes written but missing all keywords")
        else:
            subscores["notes"] = False
            feedback_parts.append("Presentation notes file not created")

        # ── Criterion 5: VLM Verification (30 pts) ─────────────────────────
        if GYM_VLM_AVAILABLE and query_vlm:
            try:
                frames = sample_trajectory_frames(traj, n=5)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                vlm_res = query_vlm(images=images, prompt=VLM_PROMPT)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    manipulated = parsed.get("manipulated_light_pollution", False)
                    contrast = parsed.get("visible_contrast", False)
                    
                    vlm_score = 0
                    if manipulated: 
                        vlm_score += 10
                        feedback_parts.append("VLM: Light pollution settings manipulated")
                    if contrast: 
                        vlm_score += 20
                        feedback_parts.append("VLM: Visual contrast in sky glow confirmed")
                        
                    score += vlm_score
                    subscores["vlm_verified"] = manipulated and contrast
                else:
                    logger.warning("VLM query returned unsuccessful")
                    feedback_parts.append("VLM check failed")
            except Exception as e:
                logger.error(f"VLM exception: {e}")
                feedback_parts.append(f"VLM exception: {str(e)}")
        else:
            # Fallback if VLM isn't available: Check config flag for database decouple
            flag_db = result.get('flag_light_pollution_database')
            if flag_db is False:
                score += 15
                feedback_parts.append("Config shows 'locations database' disabled (VLM fallback)")
            else:
                feedback_parts.append("Config 'locations database' still enabled (VLM fallback)")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}