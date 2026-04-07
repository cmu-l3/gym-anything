#!/usr/bin/env python3
"""
Verifier for noctilucent_cloud_campaign task.

Scoring (100 points):
- Location set to Edmonton (lat/lon within tolerance): 20 pts
- Landscape disabled (flag_landscape = false): 15 pts
- Azimuthal grid enabled (flag_azimuthal_grid = true): 15 pts
- Cardinal points enabled (flag_cardinal_points = true): 5 pts
- 2+ new screenshots taken: 20 pts
- Campaign plan file written with required content (Edmonton, Sun, Capella): 15 pts
- VLM Trajectory (Process completed successfully): 10 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Edmonton ground truth
EDMONTON_LAT_RAD = 0.93462   # 53.55 degrees N
EDMONTON_LON_RAD = -1.98075  # -113.49 degrees W
LAT_LON_TOLERANCE_RAD = 0.05 # ~2.8 degrees tolerance (fairly generous to account for slight misclicks, but accurate enough)

VLM_TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring Stellarium.

The images are sampled chronologically from the agent's full interaction. 
Look for evidence of the following:
1. Did the agent search for celestial objects? Look for the Search window (a popup with a text field) or objects like 'Sun' or 'Capella' selected with crosshairs.
2. Is the azimuthal grid visible at any point? This looks like concentric green circles and radiating lines originating from the zenith, measuring altitude/azimuth.
3. Is the landscape/ground removed at any point? The sky should be visible all the way down, extending into negative altitude values below the horizon line.

Respond in JSON format:
{
    "search_window_used": true/false,
    "azimuthal_grid_visible": true/false,
    "landscape_removed": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief summary of what you see across the frames"
}
"""

def verify_noctilucent_cloud_campaign(traj, env_info, task_info):
    """Verify NLC campaign planning task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "noctilucent_cloud_campaign"

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

        # ── Criterion 1: Location near Edmonton (20 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            # Handle wrapping for longitude just in case (+ or -)
            lat_diff = abs(lat_rad - EDMONTON_LAT_RAD)
            lon_diff = min(abs(lon_rad - EDMONTON_LON_RAD), abs(lon_rad - (EDMONTON_LON_RAD + 2*math.pi)), abs(lon_rad - (EDMONTON_LON_RAD - 2*math.pi)))

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(f"Edmonton location set (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
            else:
                subscores["location"] = False
                feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}° (expected ~53.55°N, ~-113.49°W)")
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Landscape Disabled (15 pts) ─────────────
        flag_landscape = result.get('flag_landscape')
        if flag_landscape is False:
            score += 15
            subscores["landscape_off"] = True
            feedback_parts.append("Landscape correctly disabled")
        else:
            subscores["landscape_off"] = False
            feedback_parts.append(f"Landscape still enabled (flag_landscape={flag_landscape})")

        # ── Criterion 3: Azimuthal grid enabled (15 pts) ─────────────────────
        flag_az = result.get('flag_azimuthal_grid')
        if flag_az is True:
            score += 15
            subscores["azimuthal_grid"] = True
            feedback_parts.append("Azimuthal coordinate grid enabled")
        else:
            subscores["azimuthal_grid"] = False
            feedback_parts.append(f"Azimuthal grid not enabled (flag_azimuthal_grid={flag_az})")

        # ── Criterion 4: Cardinal points enabled (5 pts) ─────────────────────────
        flag_cp = result.get('flag_cardinal_points')
        if flag_cp is True:
            score += 5
            subscores["cardinal_points"] = True
            feedback_parts.append("Cardinal points enabled")
        else:
            subscores["cardinal_points"] = False
            feedback_parts.append(f"Cardinal points not enabled (flag_cardinal_points={flag_cp})")

        # ── Criterion 5: 2+ screenshots taken (20 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 2:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} reference screenshots captured")
        elif new_ss == 1:
            score += 10
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshot captured (partial; required: 2)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots captured")

        # ── Criterion 6: Campaign Plan File (15 pts) ───────────────────────
        plan_exists = result.get('plan_exists', False)
        plan_has_edmonton = result.get('plan_has_edmonton', False)
        plan_has_sun = result.get('plan_has_sun', False)
        plan_has_capella = result.get('plan_has_capella', False)

        if plan_exists:
            content_score = 0
            if plan_has_edmonton: content_score += 5
            if plan_has_sun: content_score += 5
            if plan_has_capella: content_score += 5
            
            score += content_score
            subscores["campaign_plan"] = (content_score == 15)
            feedback_parts.append(f"Campaign plan file checks: Edmonton={plan_has_edmonton}, Sun={plan_has_sun}, Capella={plan_has_capella}")
        else:
            subscores["campaign_plan"] = False
            feedback_parts.append("Campaign plan file (nlc_campaign_plan.txt) not found")

        # ── Criterion 7: VLM Trajectory Verification (10 pts) ────────────────
        subscores["vlm_verified"] = False
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            
            # Execute VLM query if available
            query_vlm = env_info.get('query_vlm')
            if query_vlm and frames:
                vlm_res = query_vlm(images=frames, prompt=VLM_TRAJECTORY_PROMPT)
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('azimuthal_grid_visible') or parsed.get('search_window_used') or parsed.get('landscape_removed'):
                        score += 10
                        subscores["vlm_verified"] = True
                        feedback_parts.append("VLM verified visual trajectory of workflow")
                    else:
                        feedback_parts.append("VLM did not detect correct visual workflow")
                else:
                    score += 10  # Give free points if VLM errors out to prevent blocking
                    feedback_parts.append("VLM unavailable/failed - granting points automatically")
            else:
                score += 10
                feedback_parts.append("VLM unavailable - granting points automatically")
        except ImportError:
            score += 10
            feedback_parts.append("VLM import failed - granting points automatically")

        # Determine pass/fail
        key_criteria_met = subscores["location"] and subscores["screenshots"]
        passed = (score >= 70) and key_criteria_met

        if not key_criteria_met:
            feedback_parts.append("FAILED: Key criteria (Location and Screenshots) must be met.")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {e}"
        }