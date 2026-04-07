#!/usr/bin/env python3
"""
Verifier for qibla_solar_alignment task.

Scoring (100 points):
- 15 pts: Final location is London (latitude ~ 51.51N, longitude ~ -0.13W)
- 15 pts: Display configured (atmosphere off, azimuthal grid on)
- 20 pts: At least 2 screenshots taken
- 10 pts: Report file created during task
- 20 pts: Mecca altitude correct in report (~90 degrees)
- 20 pts: London azimuth correct in report (~119 degrees)

Pass threshold: 70 points AND London Azimuth AND Report file criteria met.
"""

import json
import tempfile
import os
import math
import re
import logging

logger = logging.getLogger(__name__)

def verify_qibla_solar_alignment(traj, env_info, task_info):
    """Verify Qibla alignment simulation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_lon_rad = metadata.get('london_lon_rad', -0.002)
    expected_lat_rad = metadata.get('london_lat_rad', 0.899)
    lat_lon_tolerance = 0.05  # ~2.8 degrees

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name

        try:
            copy_from_env("/tmp/qibla_solar_alignment_result.json", tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []
        
        # 1. Check Location (15 points) - Final location should be London
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')
        is_london = False
        
        if lat_rad is not None and lon_rad is not None:
            if (abs(lat_rad - expected_lat_rad) <= lat_lon_tolerance and 
                abs(lon_rad - expected_lon_rad) <= lat_lon_tolerance):
                is_london = True
                score += 15
                feedback_parts.append("Location successfully set to London")
            else:
                feedback_parts.append(f"Location not London: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°")
        else:
            feedback_parts.append("Could not determine final location")

        # 2. Display Configured (15 points)
        flag_atmosphere = result.get('flag_atmosphere')
        flag_grid = result.get('flag_azimuthal_grid')
        if flag_atmosphere is False and flag_grid is True:
            score += 15
            feedback_parts.append("Atmosphere off and azimuthal grid on")
        else:
            feedback_parts.append(f"Display flags incorrect (Atmo={flag_atmosphere}, Grid={flag_grid})")

        # 3. Screenshots Captured (20 points)
        new_ss = result.get('new_screenshots_count', 0)
        if new_ss >= 2:
            score += 20
            feedback_parts.append(f"{new_ss} screenshots captured")
        elif new_ss == 1:
            score += 10
            feedback_parts.append("Only 1 screenshot captured")
        else:
            feedback_parts.append("No screenshots captured")

        # 4. Report File Exists & Created During Task (10 points)
        report_exists = result.get('report_exists', False)
        report_created = result.get('report_created_during_task', False)
        report_content = result.get('report_content', '').lower()
        
        if report_exists and report_created:
            score += 10
            feedback_parts.append("Report file created")
        elif report_exists:
            feedback_parts.append("Report file exists but is stale (not modified)")
        else:
            feedback_parts.append("Report file missing")

        # 5. Mecca Altitude & London Azimuth verification (40 points)
        has_mecca_alt = False
        has_london_az = False
        
        if report_content:
            # Look for 89 or 90
            if re.search(r'\b(89|90|89\.[0-9]+|90\.0+)\b', report_content) and ('mecca' in report_content or 'altitude' in report_content):
                has_mecca_alt = True
                score += 20
                feedback_parts.append("Mecca altitude (~90°) correct in report")
            else:
                feedback_parts.append("Mecca altitude (~90°) not found in report")
                
            # Look for 118 or 119
            if re.search(r'\b(118|119|118\.[0-9]+|119\.[0-9]+)\b', report_content) and ('london' in report_content or 'azimuth' in report_content):
                has_london_az = True
                score += 20
                feedback_parts.append("London azimuth (~119°) correct in report")
            else:
                feedback_parts.append("London azimuth (~119°) not found in report")

        # Pass criteria threshold AND key flags
        key_criteria = has_london_az and report_created
        passed = score >= 70 and key_criteria

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
            "feedback": f"Error during verification: {str(e)}"
        }