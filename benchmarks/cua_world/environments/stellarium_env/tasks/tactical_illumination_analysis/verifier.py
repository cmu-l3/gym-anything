#!/usr/bin/env python3
"""
Verifier for tactical_illumination_analysis task.

Checks:
1. Location correctly set to Abbottabad
2. Landscape disabled (flag_landscape = false)
3. Azimuthal grid enabled (flag_azimuthal_grid = true)
4. Minimum of 2 Stellarium screenshots taken
5. Report written with essential thematic keywords ensuring compliance

Scoring System (100 Points Total)
- Location Configured: 25 Points
- Landscape Off: 15 Points
- Azimuthal Grid On: 15 Points
- Screenshots Captured: 25 Points
- Valid Report: 20 Points
Pass Threshold: 70
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Abbottabad precise location
ABBOTTABAD_LAT_RAD = 0.59638   # 34.17 degrees N
ABBOTTABAD_LON_RAD = 1.27829   # 73.24 degrees E
LAT_LON_TOLERANCE_RAD = 0.05   # ~2.8 degrees tolerance (protects against minor float differences/rounding)

def verify_tactical_illumination_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Evaluation execution context failure (copy_from_env missing)"}
    
    task_name = "tactical_illumination_analysis"
    
    # Secure result extraction
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name

        copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error accessing task telemetry payload: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
            
    score = 0
    feedback_parts = []
    
    # ── 1. Coordinate Validation (25 pts) ──────────────
    lat_rad = result.get('lat_rad')
    lon_rad = result.get('lon_rad')
    
    if lat_rad is not None and lon_rad is not None:
        lat_diff = abs(lat_rad - ABBOTTABAD_LAT_RAD)
        lon_diff = abs(lon_rad - ABBOTTABAD_LON_RAD)
        if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
            score += 25
            feedback_parts.append(f"Location coordinates successfully set to Abbottabad (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
        else:
            feedback_parts.append(f"Coordinates misaligned: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°")
    else:
        feedback_parts.append("Location coordinates missing from application config file")
        
    # ── 2. Disable Landscape Ground (15 pts) ───────────
    if result.get('flag_landscape') is False:
        score += 15
        feedback_parts.append("Landscape rendering disabled successfully")
    else:
        feedback_parts.append("Landscape rendering remained enabled (failure to view below-horizon objects)")
        
    # ── 3. Enable Azimuthal Grid (15 pts) ──────────────
    if result.get('flag_azimuthal_grid') is True:
        score += 15
        feedback_parts.append("Azimuthal grid overlay enabled")
    else:
        feedback_parts.append("Azimuthal grid overlay remained disabled")
        
    # ── 4. Verify Photographic Evidence (25 pts) ───────
    ss_count = result.get('new_screenshot_count', 0)
    if ss_count >= 2:
        score += 25
        feedback_parts.append(f"Captured {ss_count} unique Stellarium screenshots")
    elif ss_count == 1:
        score += 12
        feedback_parts.append("Captured only 1 screenshot (partial completion)")
    else:
        feedback_parts.append("No Stellarium screenshots taken (target objects not documented)")
        
    # ── 5. Semantic Report Verification (20 pts) ───────
    report_exists = result.get('report_exists', False)
    content = result.get('report_content', '').lower()
    
    if report_exists:
        has_loc = "abbottabad" in content
        has_date = "2011" in content
        has_moon = "moon" in content
        has_below = any(w in content for w in ["below", "negative", "horizon"])
        
        if has_loc and has_date and has_moon and has_below:
            score += 20
            feedback_parts.append("Report successfully written containing target keywords")
        else:
            score += 10
            feedback_parts.append("Report written but absent key details (partial completion)")
    else:
        feedback_parts.append("Illumination report not created")
        
    # Final tally check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }