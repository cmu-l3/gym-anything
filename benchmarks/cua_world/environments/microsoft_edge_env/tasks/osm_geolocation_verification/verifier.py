#!/usr/bin/env python3
"""
Verifier for osm_geolocation_verification task.
Checks if the agent successfully spoofed locations in Edge DevTools and captured the correct URLs.
"""

import json
import os
import re
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_osm_geolocation(traj, env_info, task_info):
    """
    Verifies the OSM Geolocation task.
    
    Criteria:
    1. Report file exists and was created during task. (10 pts)
    2. Edge Geolocation permission was granted for openstreetmap.org. (20 pts)
    3. Report contains a valid London URL. (30 pts)
    4. Report contains a valid Tokyo URL. (30 pts)
    5. The two URLs are distinct. (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Report Existence (10 pts)
    if result.get("report_exists") and result.get("report_created_during_task"):
        score += 10
        feedback.append("Report file created successfully.")
    elif result.get("report_exists"):
        score += 5
        feedback.append("Report file exists but timestamp is invalid (pre-existing?).")
    else:
        feedback.append("Report file not found.")
        return {"passed": False, "score": 0, "feedback": "Report file missing."}

    # Decode content
    try:
        content_b64 = result.get("report_content_base64", "")
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception:
        content = ""

    # 2. Check Permissions (20 pts)
    if result.get("permission_granted"):
        score += 20
        feedback.append("Geolocation permission correctly granted in Edge.")
    else:
        feedback.append("Geolocation permission NOT found in Edge settings. Did you click 'Allow'?")

    # 3 & 4. Check URL Coordinates (Regex)
    # London: ~51.5, -0.12
    # OpenStreetMap URL format: https://www.openstreetmap.org/#map=19/51.5074/-0.1278
    # Regex looks for: /LAT/LON where LAT is close to 51.5 and LON is close to -0.1
    
    london_pattern = re.compile(r'#map=\d+/51\.5\d*/-0\.1\d*')
    tokyo_pattern = re.compile(r'#map=\d+/35\.6\d*/139\.6\d*')
    
    found_london = london_pattern.search(content)
    found_tokyo = tokyo_pattern.search(content)
    
    if found_london:
        score += 30
        feedback.append(f"Valid London URL found: {found_london.group(0)}")
    else:
        feedback.append("No valid London coordinates found in report. Expected ~51.5, -0.1.")
        
    if found_tokyo:
        score += 30
        feedback.append(f"Valid Tokyo URL found: {found_tokyo.group(0)}")
    else:
        feedback.append("No valid Tokyo coordinates found in report. Expected ~35.6, 139.6.")

    # 5. Distinct Locations (10 pts)
    # Ensure the user didn't just paste the same URL twice
    if found_london and found_tokyo:
        if found_london.group(0) != found_tokyo.group(0):
            score += 10
            feedback.append("Locations are distinct.")
        else:
            feedback.append("London and Tokyo URLs appear identical.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }