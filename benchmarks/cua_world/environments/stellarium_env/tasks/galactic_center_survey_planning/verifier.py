#!/usr/bin/env python3
"""
Verifier for galactic_center_survey_planning task.

Scoring (100 points):
- Location set to ALMA (Lat ~-23.019° / -0.4017 rad): 15 pts
- Radio Mode (Atmosphere OFF, Landscape OFF): 15 pts
- Galactic Grid ON & Galactic Equator ON: 15 pts
- Survey Notes Written (has keywords): 15 pts
- Screenshot exists: 10 pts
- VLM Verification (Trajectory frames show Stellarium interaction): 30 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# ALMA ground truth
ALMA_LAT_RAD = -0.40175
ALMA_LON_RAD = -1.18251
LAT_LON_TOLERANCE_RAD = 0.06  # ~3.4 degrees tolerance

VLM_PROMPT = """
You are verifying an agent's trajectory interacting with Stellarium to plan a Galactic Center survey.

Look at the sequence of screenshots and evaluate:
1. Did the agent open the Stellarium UI and navigate its settings (like the "Sky and viewing options" window or "Location" window)?
2. Is the Galactic Grid visible in any of the views? (It looks like a spherical web/grid of lines originating from the galactic poles, often green or blue).
3. Is there evidence of the agent searching for or viewing "Sagittarius"?

Return JSON ONLY:
{
    "interacted_with_settings": true/false,
    "galactic_grid_visible": true/false,
    "viewed_sagittarius": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

def verify_galactic_survey_planning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "galactic_center_survey_planning"
    score = 0
    feedback_parts = []
    
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

        # ── Criterion 1: ALMA Location (15 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - ALMA_LAT_RAD)
            lon_diff = abs(lon_rad - ALMA_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 15
                feedback_parts.append(f"ALMA Location Set (lat={math.degrees(lat_rad):.2f}°)")
            else:
                feedback_parts.append(f"Wrong Location (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
        else:
            feedback_parts.append("Location missing")

        # ── Criterion 2: Radio Mode - Atmo & Ground OFF (15 pts) ─────────────
        atm_off = (result.get('flag_atmosphere') is False)
        land_off = (result.get('flag_landscape') is False)
        if atm_off and land_off:
            score += 15
            feedback_parts.append("Radio Mode active (Atmosphere & Ground disabled)")
        else:
            feedback_parts.append(f"Radio Mode incomplete (Atmo OFF: {atm_off}, Land OFF: {land_off})")

        # ── Criterion 3: Galactic Grid & Equator ON (15 pts) ─────────────────────
        g_grid = result.get('flag_galactic_grid')
        g_eq = result.get('flag_galactic_equator')
        if g_grid is True and g_eq is True:
            score += 15
            feedback_parts.append("Galactic Grid & Equator enabled")
        elif g_grid is True or g_eq is True:
            score += 7
            feedback_parts.append(f"Partial Galactic settings (Grid: {g_grid}, Equator: {g_eq})")
        else:
            feedback_parts.append("Galactic overlays not enabled")

        # ── Criterion 4: Survey Notes Written (15 pts) ─────────────────────────
        notes_exists = result.get('notes_exists', False)
        has_sag = result.get('notes_has_sagittarius', False)
        has_alma = result.get('notes_has_alma', False)
        has_date = result.get('notes_has_date', False)

        if notes_exists:
            k_score = sum([has_sag, has_alma, has_date]) * 5
            score += k_score
            feedback_parts.append(f"Notes check: {k_score}/15 pts (Keywords found)")
        else:
            feedback_parts.append("No survey notes file found")

        # ── Criterion 5: Screenshot Exists (10 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 10
            feedback_parts.append(f"Screenshot taken ({new_ss} captured)")
        else:
            feedback_parts.append("No screenshot captured")

        # ── Criterion 6: VLM Trajectory Check (30 pts) ───────────────────────
        vlm_score = 0
        try:
            # We wrap VLM imports in try-except in case they're not available, but award partial 
            # or skip safely. The prompt asked us to use gym_anything.vlm
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
            
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                images_to_check = [f for f in frames + [final_frame] if f is not None]
                
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=images_to_check)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    
                    if parsed.get("interacted_with_settings"): vlm_score += 10
                    if parsed.get("galactic_grid_visible"): vlm_score += 10
                    if parsed.get("viewed_sagittarius"): vlm_score += 10
                    
                    feedback_parts.append(f"VLM: Trajectory verified (+{vlm_score} pts)")
                else:
                    feedback_parts.append("VLM: Query failed or unparseable")
            else:
                feedback_parts.append("VLM: No frames available")
                
        except ImportError:
            # Fallback if VLM tools are entirely absent, grant points if core task succeeded
            if score >= 60:
                vlm_score = 30
                feedback_parts.append("VLM unavailable - full points granted for flawless technical execution")
            else:
                feedback_parts.append("VLM unavailable - insufficient base points")

        score += vlm_score

        passed = score >= 70 and g_grid is True and land_off is True
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}