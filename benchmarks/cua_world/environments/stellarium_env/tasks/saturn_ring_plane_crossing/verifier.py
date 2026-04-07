#!/usr/bin/env python3
"""
Verifier for saturn_ring_plane_crossing task.

Scoring System (100 points total):
- Location Configuration (20 points): ALMA coordinates
- Display Settings (15 points): Atmosphere and landscape disabled
- Image Capture (20 points): 3+ screenshots saved
- Article Outline (20 points): Text file with required keywords
- VLM Visual Verification (25 points): Trajectory frames show zooming in on Saturn and ring variations.

Pass Threshold: 75 points.
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# ALMA Observatory Ground Truth
ALMA_LAT_RAD = -0.40177  # -23.02 deg
ALMA_LON_RAD = -1.18247  # -67.75 deg
LAT_LON_TOLERANCE_RAD = 0.10  # ~5.7 degrees tolerance


def verify_saturn_ring_plane_crossing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "saturn_ring_plane_crossing"
    
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

        # ── Criterion 1: Observatory location (20 pts) ──────────────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - ALMA_LAT_RAD)
            lon_diff = abs(lon_rad - ALMA_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 20
                subscores["location"] = True
                feedback_parts.append(
                    f"ALMA location set correctly (lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}°)"
                )
            else:
                subscores["location"] = False
                feedback_parts.append(
                    f"Wrong location: lat={math.degrees(lat_rad):.2f}°, "
                    f"lon={math.degrees(lon_rad):.2f}° "
                    f"(expected ~-23.02°S, ~-67.75°W for ALMA)"
                )
        else:
            subscores["location"] = False
            feedback_parts.append("Location not found in config")

        # ── Criterion 2: Display Settings (15 pts) ────────────────────────
        flag_atm = result.get('flag_atmosphere')
        flag_land = result.get('flag_landscape')
        
        display_score = 0
        if flag_atm is False:
            display_score += 7.5
        if flag_land is False:
            display_score += 7.5
            
        score += display_score
        
        if display_score == 15:
            subscores["display_settings"] = True
            feedback_parts.append("Atmosphere and landscape successfully disabled")
        else:
            subscores["display_settings"] = False
            feedback_parts.append(f"Display settings incomplete (atmosphere={flag_atm}, landscape={flag_land})")

        # ── Criterion 3: Image Capture (20 pts) ───────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 3:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} reference screenshots captured (required: 3)")
        elif new_ss > 0:
            score += 5 * new_ss
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss} screenshots captured (partial; required: 3)")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots captured")

        # ── Criterion 4: Article Outline (20 pts) ──────────────
        if result.get('article_exists'):
            reqs_met = 0
            if result.get('has_saturn'): reqs_met += 1
            if result.get('has_2017'): reqs_met += 1
            if result.get('has_2021'): reqs_met += 1
            if result.get('has_2025'): reqs_met += 1
            if result.get('has_edge_on'): reqs_met += 1
            
            # Each keyword gives 4 points
            score += (reqs_met * 4)
            if reqs_met == 5:
                subscores["article"] = True
                feedback_parts.append("Article outline contains all required keywords")
            else:
                subscores["article"] = False
                feedback_parts.append(f"Article outline missing some keywords ({reqs_met}/5 found)")
        else:
            subscores["article"] = False
            feedback_parts.append("Article outline file not found")

        # ── Criterion 5: VLM Visual Verification (25 pts) ──────────────────────
        vlm_score = 0
        try:
            from gym_anything.vlm import query_vlm, sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=8)
            
            prompt = """You are analyzing screenshots from a planetarium software where the user is tracking Saturn's ring tilt over several years. Look at the sequence of images chronologically.

Assess:
1. Is Saturn clearly visible and ZOOMED IN on screen (it should be large enough to clearly see the rings, not just a tiny dot in a star field)?
2. Do you see Saturn at multiple different dates showing VARIATIONS in ring tilt (e.g., wide open vs partially closed vs completely flat/edge-on)?

Respond in JSON format:
{
    "zoomed_on_saturn": true/false,
    "multiple_ring_tilts_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("zoomed_on_saturn"):
                    vlm_score += 10
                    feedback_parts.append("VLM confirms Saturn is zoomed in")
                else:
                    feedback_parts.append("VLM did not detect zoomed-in Saturn")
                    
                if parsed.get("multiple_ring_tilts_visible"):
                    vlm_score += 15
                    feedback_parts.append("VLM confirms variation in ring tilts")
                else:
                    feedback_parts.append("VLM did not detect multiple ring tilts")
            else:
                feedback_parts.append("VLM verification failed to run")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")
            feedback_parts.append("VLM verification skipped (error)")

        score += vlm_score

        # Final pass condition: 75% or higher
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Verification failed with exception: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {str(e)}"}