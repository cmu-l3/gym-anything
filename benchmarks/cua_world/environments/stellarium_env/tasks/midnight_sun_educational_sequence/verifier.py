#!/usr/bin/env python3
"""
Verifier for midnight_sun_educational_sequence task.

Scoring System (100 points):
- Location Configured (Lat ~78.22° N): 20 points
- Display Settings Saved (Azimuthal ON, Cardinal ON, Atmosphere OFF, Landscape ON): 20 points
- 5+ Screenshots Taken: 20 points
- Lesson Plan Written (contains keywords): 20 points
- VLM Trajectory Verification (shows progression/observations): 20 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Longyearbyen coordinates
TARGET_LAT_RAD = 1.365  # ~78.22 degrees N
TARGET_LON_RAD = 0.272  # ~15.62 degrees E
LAT_LON_TOLERANCE_RAD = 0.08  # ~4.5 degrees tolerance

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent using Stellarium to observe the Midnight Sun and Polar Night in the Arctic.
The images are sampled chronologically from the agent's full interaction.

Assess if the agent completed the required observational workflow:
1. APP_OPEN: Is Stellarium open?
2. DATE_TIME_MANIPULATION: Do the frames show the agent changing the date/time (e.g., date/time dialog open, or drastically different lighting/sky states between frames)?
3. SUN_OBSERVATIONS: Can you see the Sun (or its glare) above the horizon in some frames, and a dark/twilight sky (Sun below horizon) in others?
4. DIAGRAM_SETUP: Are the azimuthal coordinate grid (green/blue curved lines) and cardinal directions (N, S, E, W) visible on the screen?

Respond in strict JSON format:
{
    "app_open": true/false,
    "date_time_manipulation": true/false,
    "sun_observations": true/false,
    "diagram_setup": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible across the frames"
}
"""

def verify_midnight_sun_sequence(traj, env_info, task_info):
    """Verify the midnight sun educational sequence task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "midnight_sun_educational_sequence"
    score = 0
    feedback_parts = []
    
    try:
        # Copy result JSON from VM
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name

        try:
            copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        # ── 1. Location Configured (20 points) ──
        lat_rad = result.get('lat_rad')
        
        if lat_rad is not None:
            lat_diff = abs(lat_rad - TARGET_LAT_RAD)
            if lat_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                feedback_parts.append(f"Location set correctly (lat={math.degrees(lat_rad):.2f}° N)")
            else:
                feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}° N (expected ~78.22° N)")
        else:
            feedback_parts.append("Location not found in config")

        # ── 2. Display Settings Saved (20 points) ──
        settings_score = 0
        if result.get('flag_azimuthal_grid') is True: settings_score += 5
        if result.get('flag_cardinal_points') is True: settings_score += 5
        if result.get('flag_atmosphere') is False: settings_score += 5
        if result.get('flag_landscape') is True: settings_score += 5
        
        score += settings_score
        if settings_score == 20:
            feedback_parts.append("All display settings saved correctly")
        else:
            feedback_parts.append(f"Partial display settings saved ({settings_score}/20 pts)")

        # ── 3. Screenshots Taken (20 points) ──
        ss_count = result.get('new_screenshot_count', 0)
        if ss_count >= 5:
            score += 20
            feedback_parts.append(f"{ss_count} screenshots captured (required: 5)")
        elif ss_count > 0:
            score += (ss_count * 4) # 4 pts per screenshot
            feedback_parts.append(f"Only {ss_count} screenshots captured (required: 5)")
        else:
            feedback_parts.append("No screenshots captured")

        # ── 4. Lesson Plan Content (20 points) ──
        if result.get('lesson_plan_exists', False):
            lp_score = 0
            if result.get('has_longyearbyen'): lp_score += 5
            if result.get('has_winter_dec'): lp_score += 5
            if result.get('has_summer_jun'): lp_score += 5
            if result.get('has_horizon_obs'): lp_score += 5
            
            score += lp_score
            if lp_score > 0:
                feedback_parts.append(f"Lesson plan written with appropriate keywords ({lp_score}/20 pts)")
            else:
                feedback_parts.append("Lesson plan exists but lacks required observational keywords")
        else:
            feedback_parts.append("Lesson plan file not found")

        # ── 5. VLM Trajectory Verification (20 points) ──
        # Try importing from the newer gym_anything standard
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            query_vlm = env_info.get('query_vlm')
            
            if query_vlm:
                frames = sample_trajectory_frames(traj, n=4)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=images)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    vlm_score = 0
                    if parsed.get("app_open"): vlm_score += 5
                    if parsed.get("date_time_manipulation"): vlm_score += 5
                    if parsed.get("sun_observations"): vlm_score += 5
                    if parsed.get("diagram_setup"): vlm_score += 5
                    
                    score += vlm_score
                    feedback_parts.append(f"VLM trajectory visual verification: {vlm_score}/20 pts")
                else:
                    logger.warning("VLM query failed or returned no success, giving partial fallback credit.")
                    score += 10 # Fallback if VLM fails structurally
                    feedback_parts.append("VLM unavailable, applying fallback score for process.")
            else:
                score += 10 # Fallback if query_vlm not provided
                feedback_parts.append("VLM query function not provided, applying fallback process score.")
        except ImportError:
            # Fallback for environments lacking the import
            score += 10
            feedback_parts.append("VLM dependencies not found, applying fallback process score.")

        # Determine pass/fail
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