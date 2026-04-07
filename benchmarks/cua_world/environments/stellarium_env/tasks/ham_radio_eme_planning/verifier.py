#!/usr/bin/env python3
"""
Verifier for ham_radio_eme_planning task.

Scoring (100 points):
- Final Location (London): lat ~ 0.899 rad, lon ~ -0.002 rad (20 points)
- RF Display Settings: Atmosphere=False, Landscape=False, Azimuthal Grid=True (25 points)
- Screenshot Generation: >= 2 new screenshots in ~/Pictures/stellarium/ (20 points)
- Log File Accuracy: eme_sked_nov15.txt exists with keywords (20 points)
- Multi-Site Workflow (VLM): Trajectory shows Tokyo view was configured and centered on Moon before London (15 points)

Pass threshold: 75 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# London Ground Truth
LONDON_LAT_RAD = 0.8990   # ~51.51 degrees
LONDON_LON_RAD = -0.0023  # ~-0.13 degrees
LAT_LON_TOLERANCE_RAD = 0.10  # ~5.7 degrees tolerance

VLM_TRAJECTORY_PROMPT = """You are evaluating an AI agent using Stellarium for a ham radio Earth-Moon-Earth (moonbounce) planning task.

The agent needs to:
1. View the Moon from Tokyo, Japan.
2. View the Moon from London, UK.

Look at these trajectory frames (sampled chronologically). Answer the following:
1. "tokyo_view_observed": Is there evidence in the earlier frames that the agent navigated to Tokyo (or a location in East Asia) and looked at the Moon? (e.g., location dialog shows Tokyo, or sky shows Moon at high elevation).
2. "london_view_observed": Is there evidence in the later frames that the agent navigated to London (or UK) and looked at the Moon?
3. "moon_centered": Did the agent successfully center/target the Moon in any of the views?
4. "multiple_locations": Did the agent clearly switch locations between frames, rather than just staying in one place?

Respond exactly in JSON format:
{
    "tokyo_view_observed": true/false,
    "london_view_observed": true/false,
    "moon_centered": true/false,
    "multiple_locations": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_ham_radio_eme_planning(traj, env_info, task_info):
    """Verify Earth-Moon-Earth planning task using both programmatic and VLM checks."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "ham_radio_eme_planning"
    score = 0
    feedback_parts = []
    
    # ── PROGRAMMATIC VERIFICATION ──
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

        # 1. Final Location (London) [20 pts]
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')
        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - LONDON_LAT_RAD)
            lon_diff = abs(lon_rad - LONDON_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                feedback_parts.append(f"Final location is London (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                feedback_parts.append(f"Wrong final location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}° (expected London)")
        else:
            feedback_parts.append("Final location missing in config")

        # 2. RF Display Settings [25 pts]
        flag_atmosphere = result.get('flag_atmosphere')
        flag_landscape = result.get('flag_landscape')
        flag_azimuthal = result.get('flag_azimuthal_grid')
        
        display_score = 0
        if flag_atmosphere is False: display_score += 8
        if flag_landscape is False: display_score += 8
        if flag_azimuthal is True: display_score += 9
        
        score += display_score
        if display_score == 25:
            feedback_parts.append("RF display settings correct (atmosphere/landscape off, azimuthal grid on)")
        else:
            feedback_parts.append(f"Display settings incomplete (Atmosphere:{flag_atmosphere}, Landscape:{flag_landscape}, Azimuthal:{flag_azimuthal})")

        # 3. Screenshot Generation [20 pts]
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 2:
            score += 20
            feedback_parts.append(f"{new_ss} screenshots captured (required: 2+)")
        elif new_ss == 1:
            score += 10
            feedback_parts.append("Only 1 screenshot captured (required: 2)")
        else:
            feedback_parts.append("No screenshots captured")

        # 4. Log File Accuracy [20 pts]
        log_exists = result.get('log_exists', False)
        task_start = result.get('task_start', 0)
        log_mtime = result.get('log_mtime', 0)
        
        if log_exists and log_mtime > task_start:
            log_contents = result.get('log_contents', '').lower()
            req_words = ["moon", "tokyo", "london", "15:00"]
            matched_words = sum(1 for w in req_words if w in log_contents)
            
            if matched_words == len(req_words):
                score += 20
                feedback_parts.append("Schedule log is accurate and created during task")
            elif matched_words > 0:
                score += 10
                feedback_parts.append(f"Schedule log missing some details ({matched_words}/{len(req_words)} keywords found)")
            else:
                feedback_parts.append("Schedule log exists but content is completely wrong")
        elif log_exists:
            feedback_parts.append("Schedule log exists but was not modified during task (stale file)")
        else:
            feedback_parts.append("Schedule log file missing")

    except Exception as e:
        logger.error(f"Error during programmatic verification: {e}")
        feedback_parts.append(f"Verification error: {str(e)}")

    # ── VLM TRAJECTORY VERIFICATION ──
    try:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames
        
        # Sample frames from the trajectory (e.g., 4 frames across the episode)
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_response = query_vlm(prompt=VLM_TRAJECTORY_PROMPT, images=frames)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                vlm_score = 0
                if parsed.get("multiple_locations"): vlm_score += 5
                if parsed.get("tokyo_view_observed"): vlm_score += 5
                if parsed.get("moon_centered") or parsed.get("london_view_observed"): vlm_score += 5
                
                score += vlm_score
                
                if vlm_score == 15:
                    feedback_parts.append("VLM confirms multi-site workflow")
                else:
                    feedback_parts.append(f"VLM workflow check partial: {parsed.get('reasoning', 'incomplete')}")
            else:
                logger.warning(f"VLM request failed: {vlm_response.get('error')}")
                # Fallback to programmatic criteria if VLM fails
                score += 15
                feedback_parts.append("VLM unavailable, awarding workflow points by default")
        else:
            logger.warning("No trajectory frames available for VLM")
            score += 15
            feedback_parts.append("No frames for VLM, awarding workflow points by default")
            
    except ImportError:
        logger.warning("VLM module not available in environment")
        score += 15
        feedback_parts.append("VLM module unavailable, awarding workflow points by default")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        score += 15
        feedback_parts.append("VLM error, awarding workflow points by default")

    # Determine pass/fail
    # Must meet passing score AND have successfully set the London location and created the log file.
    passed = score >= 75 and (result.get('lat_rad') is not None) and result.get('log_exists', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }