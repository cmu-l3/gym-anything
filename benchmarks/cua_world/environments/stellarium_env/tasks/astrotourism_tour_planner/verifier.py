#!/usr/bin/env python3
"""
Verifier for astrotourism_tour_planner task.

Scoring (100 points):
- Location latitude correct (-44.00° / -0.7679 rad): 15 pts
- Location longitude correct (170.47° / 2.9753 rad): 10 pts
- Atmosphere disabled: 10 pts
- Ground/landscape disabled: 5 pts
- Constellation lines enabled: 10 pts
- Constellation labels enabled: 10 pts
- 3+ screenshots captured: 20 pts
- Briefing file exists: 5 pts
- Briefing mentions all 3 objects (Crux, Magellanic, Alpha Centauri): 15 pts (5 each)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Aoraki Mackenzie Dark Sky Reserve ground truth
TARGET_LAT_RAD = -0.76794
TARGET_LON_RAD = 2.97528
LAT_TOLERANCE_RAD = 0.05
LON_TOLERANCE_RAD = 0.10

def verify_astrotourism_tour_planner(traj, env_info, task_info):
    """Verify astro-tourism session planning task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "astrotourism_tour_planner"

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

        # Criterion 1: Location latitude (15 pts)
        lat_rad = result.get('lat_rad')
        if lat_rad is not None:
            lat_diff = abs(lat_rad - TARGET_LAT_RAD)
            if lat_diff <= LAT_TOLERANCE_RAD:
                score += 15
                subscores["latitude"] = True
                feedback_parts.append(f"Latitude correct ({math.degrees(lat_rad):.2f}°)")
            else:
                subscores["latitude"] = False
                feedback_parts.append(f"Wrong latitude ({math.degrees(lat_rad):.2f}°, expected ~-44.00°)")
        else:
            subscores["latitude"] = False
            feedback_parts.append("Latitude not found in config")

        # Criterion 2: Location longitude (10 pts)
        lon_rad = result.get('lon_rad')
        if lon_rad is not None:
            lon_diff = abs(lon_rad - TARGET_LON_RAD)
            if lon_diff <= LON_TOLERANCE_RAD:
                score += 10
                subscores["longitude"] = True
                feedback_parts.append(f"Longitude correct ({math.degrees(lon_rad):.2f}°)")
            else:
                subscores["longitude"] = False
                feedback_parts.append(f"Wrong longitude ({math.degrees(lon_rad):.2f}°, expected ~170.47°)")
        else:
            subscores["longitude"] = False
            feedback_parts.append("Longitude not found in config")

        # Criterion 3: Atmosphere disabled (10 pts)
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is False:
            score += 10
            subscores["atmosphere_off"] = True
            feedback_parts.append("Atmosphere disabled")
        else:
            subscores["atmosphere_off"] = False
            feedback_parts.append("Atmosphere not disabled")

        # Criterion 4: Ground disabled (5 pts)
        flag_landscape = result.get('flag_landscape')
        if flag_landscape is False:
            score += 5
            subscores["landscape_off"] = True
            feedback_parts.append("Landscape/ground disabled")
        else:
            subscores["landscape_off"] = False
            feedback_parts.append("Landscape/ground not disabled")

        # Criterion 5: Constellation lines enabled (10 pts)
        flag_lines = result.get('flag_constellation_drawing')
        if flag_lines is True:
            score += 10
            subscores["constellation_lines"] = True
            feedback_parts.append("Constellation lines enabled")
        else:
            subscores["constellation_lines"] = False
            feedback_parts.append("Constellation lines not enabled")

        # Criterion 6: Constellation labels enabled (10 pts)
        flag_names = result.get('flag_constellation_name')
        if flag_names is True:
            score += 10
            subscores["constellation_labels"] = True
            feedback_parts.append("Constellation labels enabled")
        else:
            subscores["constellation_labels"] = False
            feedback_parts.append("Constellation labels not enabled")

        # Criterion 7: Screenshots (20 pts)
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 3:
            score += 20
            subscores["screenshots"] = True
            feedback_parts.append(f"{new_ss} screenshots captured")
        elif new_ss > 0:
            score += new_ss * 6  # Partial credit
            subscores["screenshots"] = False
            feedback_parts.append(f"Only {new_ss}/3 screenshots captured")
        else:
            subscores["screenshots"] = False
            feedback_parts.append("No screenshots captured")

        # Criterion 8 & 9: Briefing file and content (20 pts total)
        briefing_exists = result.get('briefing_exists', False)
        briefing_during_task = result.get('briefing_created_during_task', False)
        
        if briefing_exists and briefing_during_task:
            score += 5
            subscores["briefing_exists"] = True
            feedback_parts.append("Tour briefing file created")
            
            # Content checks
            has_crux = result.get('briefing_has_crux', False)
            has_lmc = result.get('briefing_has_magellanic', False)
            has_cen = result.get('briefing_has_centauri', False)
            
            objects_found = 0
            if has_crux: objects_found += 1; score += 5
            if has_lmc: objects_found += 1; score += 5
            if has_cen: objects_found += 1; score += 5
            
            subscores["briefing_content"] = (objects_found == 3)
            feedback_parts.append(f"Briefing mentions {objects_found}/3 required objects")
        elif briefing_exists:
            subscores["briefing_exists"] = False
            feedback_parts.append("Briefing file existed before task (not modified during task)")
        else:
            subscores["briefing_exists"] = False
            feedback_parts.append("Tour briefing file missing")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {str(e)}",
            "details": {}
        }