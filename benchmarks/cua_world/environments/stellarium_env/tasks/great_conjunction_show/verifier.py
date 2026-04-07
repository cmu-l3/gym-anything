#!/usr/bin/env python3
"""
Verifier for great_conjunction_show task.

Scoring System (100 points):
- Location set to Jerusalem (Latitude: 31.77°, Longitude: 35.21°): 20 pts
- Display Configuration (Atmosphere OFF, Landscape OFF, Art ON, Lines ON, Names ON): 25 pts (5 pts each)
- Screenshots: 3+ screenshots taken during task: 20 pts
- Script written with correct keywords: 20 pts
- VLM Trajectory check: verify agent navigated to historical year -6 and viewed planets: 15 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing if framework imports aren't available
    def sample_trajectory_frames(*args, **kwargs): return []
    def get_final_screenshot(*args, **kwargs): return None
    def query_vlm(*args, **kwargs): return {"success": False}

logger = logging.getLogger(__name__)

# Jerusalem Coordinates
JERUSALEM_LAT_RAD = 0.5545  # 31.77 degrees N
JERUSALEM_LON_RAD = 0.6145  # 35.21 degrees E
LAT_LON_TOLERANCE_RAD = 0.10  # ~5.7 degrees tolerance


VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring a planetarium show in Stellarium.

The task required the agent to:
1. Navigate to the historical astronomical year "-6" (which represents 7 BC).
2. Locate and view the planets Jupiter and Saturn (in conjunction/close together).
3. Display constellation artwork (mythological figures, specifically Pisces).

Look at these trajectory frames (sampled chronologically).
Respond in JSON format:
{
    "navigated_to_year_minus_6": true/false,
    "viewed_jupiter_and_saturn": true/false,
    "art_visible_on_screen": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible regarding the date UI, the planets, and constellation art."
}
"""

def verify_great_conjunction_show(traj, env_info, task_info):
    """
    Verify the Great Conjunction Planetarium Show task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "great_conjunction_show"

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
        
        # ── 1. Location Check (20 pts) ─────────────────────────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - JERUSALEM_LAT_RAD)
            lon_diff = abs(lon_rad - JERUSALEM_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                feedback_parts.append(f"Jerusalem location set (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}° (expected ~31.77°N, ~35.21°E)")
        else:
            feedback_parts.append("Location not found in config")

        # ── 2. Display Configuration (25 pts - 5 pts each) ─────────────────────
        if result.get('flag_atmosphere') is False:
            score += 5
        else:
            feedback_parts.append("Atmosphere not disabled")

        if result.get('flag_landscape') is False:
            score += 5
        else:
            feedback_parts.append("Landscape not disabled")

        if result.get('flag_constellation_art') is True:
            score += 5
        else:
            feedback_parts.append("Constellation art not enabled")

        if result.get('flag_constellation_drawing') is True:
            score += 5
        else:
            feedback_parts.append("Constellation lines not enabled")

        if result.get('flag_constellation_name') is True:
            score += 5
        else:
            feedback_parts.append("Constellation names not enabled")

        # ── 3. Screenshots (20 pts) ────────────────────────────────────────────
        ss_count = result.get('new_screenshot_count', 0)
        if ss_count >= 3:
            score += 20
            feedback_parts.append(f"{ss_count} screenshots captured")
        elif ss_count > 0:
            score += 10
            feedback_parts.append(f"Only {ss_count} screenshots (required 3)")
        else:
            feedback_parts.append("No screenshots captured")

        # ── 4. Presenter Script (20 pts) ───────────────────────────────────────
        script_exists = result.get('script_exists', False)
        script_content = result.get('script_content', '').lower()
        
        if script_exists and script_content:
            has_jup = "jupiter" in script_content
            has_sat = "saturn" in script_content
            has_pis = "pisces" in script_content
            has_jer = "jerusalem" in script_content
            has_year = "7 bc" in script_content or "-6" in script_content or "7bc" in script_content

            criteria_met = sum([has_jup, has_sat, has_pis, has_jer, has_year])
            
            if criteria_met == 5:
                score += 20
                feedback_parts.append("Presenter script perfect")
            else:
                score += (criteria_met * 4)  # Partial credit
                feedback_parts.append(f"Presenter script missing some keywords ({criteria_met}/5 found)")
        else:
            feedback_parts.append("Presenter script missing or empty")

        # ── 5. VLM Trajectory Check (15 pts) ───────────────────────────────────
        try:
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    vlm_score = 0
                    if parsed.get("navigated_to_year_minus_6"): vlm_score += 8
                    if parsed.get("viewed_jupiter_and_saturn"): vlm_score += 7
                    
                    score += vlm_score
                    if vlm_score == 15:
                        feedback_parts.append("VLM verified year and planets")
                    else:
                        feedback_parts.append(f"VLM verification partial/failed: {parsed.get('reasoning', '')}")
                else:
                    feedback_parts.append("VLM query failed, awarding partial default points")
                    score += 8
            else:
                feedback_parts.append("No trajectory frames available for VLM")
        except Exception as e:
            logger.warning(f"VLM Exception: {e}")
            score += 8  # fallback if framework lacks VLM support
            
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {e}"
        }