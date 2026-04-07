#!/usr/bin/env python3
"""
Verifier for barnards_star_proper_motion task.

Scoring System (100 points):
- Location set to Palomar Observatory (Lat: ~33.35, Lon: ~-116.86): 10 pts
- Display Configuration (Atmosphere OFF, Ground OFF, Equatorial Grid ON): 20 pts
- Final Epoch set to ~2050 (JD ~ 2469807): 15 pts
- 2+ new screenshots captured: 25 pts
- Educational Summary file created with required keywords: 30 pts

VLM Verification: Check trajectory for equatorial grid & zoomed star visibility.
Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logger = logging.getLogger(__name__)

# Palomar Observatory
PALOMAR_LAT_RAD = 0.5820   # 33.35 degrees N
PALOMAR_LON_RAD = -2.0396  # -116.86 degrees W
LAT_LON_TOLERANCE_RAD = 0.10

# 2050-01-01 JD
JD_2050 = 2469807.5
JD_TOLERANCE = 365 # allow within ~1 year of 2050

REQUIRED_KEYWORDS = ["barnard", "1950", "2050", "proper motion"]

VLM_PROMPT = """You are evaluating an AI agent's performance in Stellarium. 
The agent was asked to find "Barnard's Star", zoom in on it, and turn on the equatorial coordinate grid (blue grid lines representing Right Ascension and Declination).

Look at these screenshots from the agent's workflow. 
1. Is the equatorial coordinate grid (blue lines overlaying the sky) visible in any of the active frames?
2. Did the agent zoom in on a targeted star (ideally Barnard's Star, typically indicated by a selection reticle, text label, or centered view)?

Respond in JSON format:
{
    "grid_visible": true/false,
    "star_targeted": true/false,
    "reasoning": "Brief explanation of what is visible"
}"""

def verify_barnards_star_proper_motion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "barnards_star_proper_motion"
    
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
        
        # ── 1. Location (10 pts) ──────────────────────────────────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            if abs(lat_rad - PALOMAR_LAT_RAD) <= LAT_LON_TOLERANCE_RAD and abs(lon_rad - PALOMAR_LON_RAD) <= LAT_LON_TOLERANCE_RAD:
                score += 10
                feedback_parts.append("Location correctly set to Palomar.")
            else:
                feedback_parts.append(f"Location incorrect (lat: {math.degrees(lat_rad):.2f}, lon: {math.degrees(lon_rad):.2f}).")
        else:
            feedback_parts.append("Failed to extract location.")

        # ── 2. Display Configuration (20 pts) ─────────────────────────────────────
        flag_atm = result.get('flag_atmosphere')
        flag_land = result.get('flag_landscape')
        flag_grid = result.get('flag_equatorial_grid')

        display_score = 0
        if flag_atm is False:
            display_score += 6
            feedback_parts.append("Atmosphere OFF.")
        else:
            feedback_parts.append("Atmosphere still ON.")
            
        if flag_land is False:
            display_score += 6
            feedback_parts.append("Ground OFF.")
        else:
            feedback_parts.append("Ground still ON.")
            
        if flag_grid is True:
            display_score += 8
            feedback_parts.append("Equatorial Grid ON.")
        else:
            feedback_parts.append("Equatorial Grid OFF.")
            
        score += display_score

        # ── 3. Final Epoch (15 pts) ───────────────────────────────────────────────
        sky_time = result.get('preset_sky_time')
        if sky_time is not None:
            if abs(sky_time - JD_2050) <= JD_TOLERANCE:
                score += 15
                feedback_parts.append("Final date successfully set to ~2050.")
            else:
                feedback_parts.append(f"Final date incorrect (JD {sky_time:.1f}, expected ~{JD_2050}).")
        else:
            feedback_parts.append("Could not determine final simulation time.")

        # ── 4. Screenshots (25 pts) ───────────────────────────────────────────────
        ss_count = result.get('new_screenshot_count', 0)
        if ss_count >= 2:
            score += 25
            feedback_parts.append(f"Captured {ss_count} screenshots.")
        elif ss_count == 1:
            score += 10
            feedback_parts.append("Only captured 1 screenshot (expected at least 2).")
        else:
            feedback_parts.append("No screenshots captured.")

        # ── 5. Notes Content (30 pts) ─────────────────────────────────────────────
        notes_exists = result.get('notes_exists', False)
        notes_content = result.get('notes_content', '').lower()
        
        if notes_exists:
            found_keywords = [kw for kw in REQUIRED_KEYWORDS if kw in notes_content]
            kw_ratio = len(found_keywords) / len(REQUIRED_KEYWORDS)
            score += int(30 * kw_ratio)
            
            if kw_ratio == 1.0:
                feedback_parts.append("Summary notes file perfect.")
            elif kw_ratio > 0:
                feedback_parts.append(f"Summary notes missing some keywords. Found: {found_keywords}")
            else:
                feedback_parts.append("Summary notes file empty or entirely missing required content.")
        else:
            feedback_parts.append("Summary notes file missing.")

        # ── 6. VLM Check (Diagnostic Bonus / Validation) ──────────────────────────
        if VLM_AVAILABLE and traj:
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            all_frames = frames + ([final_frame] if final_frame else [])
            
            if all_frames:
                try:
                    vlm_res = query_vlm(images=all_frames, prompt=VLM_PROMPT)
                    if vlm_res and vlm_res.get("success"):
                        parsed = vlm_res.get("parsed", {})
                        grid_vis = parsed.get("grid_visible", False)
                        star_targ = parsed.get("star_targeted", False)
                        
                        if grid_vis and star_targ:
                            feedback_parts.append("[VLM] Confirmed equatorial grid and targeted star visible.")
                            # Bonus points to ensure passing if they slightly missed keywords but did the work visually
                            score = min(100, score + 10) 
                        else:
                            feedback_parts.append(f"[VLM] Grid visible: {grid_vis}, Star targeted: {star_targ}.")
                except Exception as e:
                    logger.warning(f"VLM query failed during verification: {e}")

        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }

    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }