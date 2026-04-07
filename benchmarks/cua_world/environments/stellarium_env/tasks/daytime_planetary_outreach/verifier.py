#!/usr/bin/env python3
"""
Verifier for daytime_planetary_outreach task.

Scoring (100 points total):
- Location Configured (Griffith Obs): 15 pts
- Display flags (Atmosphere ON, Azimuthal ON, Labels ON): 25 pts
- 3+ Screenshots Captured: 20 pts
- Outreach Document Created with keywords: 20 pts
- VLM Verification (Trajectory shows daytime sky progression): 20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Griffith Observatory ground truth
GRIFFITH_LAT_RAD = 0.59547   # 34.118 degrees N
GRIFFITH_LON_RAD = -2.06470  # -118.300 degrees W
LAT_LON_TOLERANCE_RAD = 0.05  # ~2.8 degrees tolerance

VLM_PROMPT = """You are evaluating an agent's trajectory screenshots for a Stellarium daytime observation task.
The agent was asked to find Venus, Jupiter, and Sirius during broad daylight.

Examine these trajectory screenshots carefully:
1. Is a bright blue daytime sky visible in any of the Stellarium views (meaning atmosphere simulation was turned on)?
2. Do you see evidence of target acquisition? (e.g., centering on a bright object like Venus, Jupiter, or Sirius)
3. Do the frames show a progression of searching for different targets?

Respond in JSON format:
{
    "daytime_sky_visible": true/false,
    "targets_acquired": true/false,
    "progression_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_daytime_planetary_outreach(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "daytime_planetary_outreach"

    # Copy result JSON from VM
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
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported result: {e}"}

    score = 0
    feedback_parts = []
    
    # ── Criterion 1: Location set to Griffith Observatory (15 pts) ──────────
    lat_rad = result.get('lat_rad')
    lon_rad = result.get('lon_rad')

    if lat_rad is not None and lon_rad is not None:
        lat_diff = abs(lat_rad - GRIFFITH_LAT_RAD)
        lon_diff = abs(lon_rad - GRIFFITH_LON_RAD)

        if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
            score += 15
            feedback_parts.append(f"Griffith location set (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
        else:
            feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°")
    else:
        feedback_parts.append("Location not found in config")

    # ── Criterion 2: Display flags configured for daytime pointing (25 pts) ─
    flag_atmosphere = result.get('flag_atmosphere')
    flag_azimuthal = result.get('flag_azimuthal_grid')
    flag_star_name = result.get('flag_star_name')
    flag_planets = result.get('flag_planets_hints')

    flags_met = 0
    if flag_atmosphere is True:
        flags_met += 1
        feedback_parts.append("Atmosphere ON")
    else:
        feedback_parts.append("Atmosphere OFF (needs to be ON)")
        
    if flag_azimuthal is True:
        flags_met += 1
        feedback_parts.append("Azimuthal Grid ON")
    else:
        feedback_parts.append("Azimuthal Grid OFF")

    if flag_star_name is True and flag_planets is True:
        flags_met += 2
        feedback_parts.append("Planet & Star Labels ON")
    else:
        feedback_parts.append("Labels not fully enabled")

    # 25 points total (scaled based on 4 flags met)
    score += int((flags_met / 4) * 25)

    # ── Criterion 3: 3+ Screenshots Captured (20 pts) ───────────────────────
    new_ss = result.get('new_screenshot_count', 0)
    if new_ss >= 3:
        score += 20
        feedback_parts.append(f"{new_ss} screenshots captured")
    elif new_ss > 0:
        score += int((new_ss / 3) * 20)
        feedback_parts.append(f"Only {new_ss}/3 screenshots captured")
    else:
        feedback_parts.append("No screenshots captured")

    # ── Criterion 4: Outreach Document Created with keywords (20 pts) ───────
    plan_exists = result.get('plan_exists', False)
    keywords_found = result.get('keywords_found', [])
    expected_keywords = task_info.get('metadata', {}).get('keywords', ["griffith", "june", "venus", "jupiter", "sirius"])
    
    if plan_exists:
        match_count = len(keywords_found)
        if match_count == len(expected_keywords):
            score += 20
            feedback_parts.append("Outreach plan complete with all keywords")
        elif match_count > 0:
            score += int((match_count / len(expected_keywords)) * 20)
            feedback_parts.append(f"Outreach plan partial (missing {len(expected_keywords)-match_count} keywords)")
        else:
            feedback_parts.append("Outreach plan created but missing required content")
    else:
        feedback_parts.append("Outreach plan document not created")

    # ── Criterion 5: VLM Verification (20 pts) ──────────────────────────────
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        vlm_images = []
        if frames: vlm_images.extend(frames)
        if final: vlm_images.append(final)
        
        if vlm_images:
            vlm_resp = query_vlm(images=vlm_images, prompt=VLM_PROMPT)
            if vlm_resp and vlm_resp.get("success") and "parsed" in vlm_resp:
                parsed = vlm_resp["parsed"]
                vlm_score = 0
                if parsed.get("daytime_sky_visible"): vlm_score += 10
                if parsed.get("targets_acquired"): vlm_score += 10
                
                confidence = parsed.get("confidence", "low")
                if confidence == "low": vlm_score = int(vlm_score * 0.7)
                
                score += vlm_score
                feedback_parts.append(f"VLM verification scored {vlm_score}/20")
            else:
                feedback_parts.append("VLM query failed or format invalid")
        else:
            feedback_parts.append("No images available for VLM verification")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification skipped (error)")

    # Final evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }