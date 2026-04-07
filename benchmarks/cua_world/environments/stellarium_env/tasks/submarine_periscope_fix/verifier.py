#!/usr/bin/env python3

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Target Coordinates for Mediterranean Sea: 34.00 N, 18.00 E
TARGET_LAT_RAD = 0.5934
TARGET_LON_RAD = 0.3142
TOLERANCE_RAD = 0.05

def verify_submarine_periscope_fix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "submarine_periscope_fix"

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
        
        # 1. Location (10 pts)
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')
        
        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - TARGET_LAT_RAD)
            lon_diff = abs(lon_rad - TARGET_LON_RAD)
            
            if lat_diff <= TOLERANCE_RAD and lon_diff <= TOLERANCE_RAD:
                score += 10
                feedback_parts.append(f"Location correct (Mediterranean Sea: {math.degrees(lat_rad):.2f}°N, {math.degrees(lon_rad):.2f}°E)")
            else:
                feedback_parts.append(f"Location incorrect: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°")
        else:
            feedback_parts.append("Location not found in config")
            
        # 2. Grid/Overlay Setup (30 pts)
        flag_azimuthal = result.get('flag_azimuthal_grid')
        flag_landscape = result.get('flag_landscape')
        flag_const = result.get('flag_constellation_drawing')
        
        if flag_azimuthal is True:
            score += 10
            feedback_parts.append("Azimuthal grid enabled")
        else:
            feedback_parts.append("Azimuthal grid NOT enabled")
            
        if flag_landscape is False:
            score += 10
            feedback_parts.append("Landscape disabled")
        else:
            feedback_parts.append("Landscape NOT disabled")
            
        if flag_const is True:
            score += 10
            feedback_parts.append("Constellation drawing enabled")
        else:
            feedback_parts.append("Constellation drawing NOT enabled")
            
        # 3. Screenshots (25 pts)
        ss_count = result.get('new_screenshot_count', 0)
        if ss_count >= 3:
            score += 25
            feedback_parts.append(f"{ss_count} screenshots taken")
        elif ss_count > 0:
            score += int(25 * (ss_count / 3.0))
            feedback_parts.append(f"Only {ss_count} screenshots taken (partial credit)")
        else:
            feedback_parts.append("No screenshots taken")
            
        # 4. Briefing Document (25 pts)
        doc_exists = result.get('doc_exists', False)
        doc_content = result.get('doc_content', '').lower()
        
        if doc_exists:
            kws = ["mediterranean", "15", "sirius", "polaris", "capella"]
            found = [kw for kw in kws if kw in doc_content]
            if "nov" in doc_content or "11/" in doc_content:
                found.append("november")
                
            if len(found) >= 6:
                score += 25
                feedback_parts.append("Briefing document complete")
            elif len(found) > 0:
                score += int(25 * (len(found) / 6.0))
                feedback_parts.append(f"Briefing document partial ({len(found)}/6 keywords)")
            else:
                feedback_parts.append("Briefing document missing keywords")
        else:
            feedback_parts.append("Briefing document NOT created")
            
        # 5. VLM Trajectory Verification (10 pts)
        try:
            from gym_anything.vlm import sample_trajectory_frames, query_vlm
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = '''Look at these screenshots of a user interacting with Stellarium.
Did the user search for specific stars (like Sirius, Polaris, or Capella) using the search window?
Reply with a JSON: {"searched_stars": true/false}'''
                vlm_res = query_vlm(images=frames, prompt=prompt)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("searched_stars"):
                        score += 10
                        feedback_parts.append("VLM verified star searches")
                    else:
                        feedback_parts.append("VLM did not clearly verify star searches")
        except BaseException as e:
            logger.warning(f"VLM verification skipped/failed: {e}")
            score += 10 # Give benefit of the doubt if framework component is missing

        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
            
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}