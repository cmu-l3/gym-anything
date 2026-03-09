#!/usr/bin/env python3
"""
Verifier for noaa_tide_transit_planning task.

Verifies:
1. Bookmarks created correctly (20 pts)
2. History shows NOAA visits (20 pts)
3. JSON file exists and is valid (10 pts)
4. Data content accuracy (The Battery & Kings Point) (50 pts)

The verifier fetches GROUND TRUTH data from the NOAA CO-OPS API at runtime
to ensure accuracy for the specific date (2025-10-15).
"""

import json
import os
import tempfile
import logging
import urllib.request
import ssl
from datetime import datetime

logger = logging.getLogger(__name__)

# Constants
TARGET_DATE = "20251015"  # YYYYMMDD
STATION_BATTERY = "8518750"
STATION_KINGS = "8516945"

def fetch_noaa_predictions(station_id, date_str):
    """
    Fetch authoritative predictions from NOAA CO-OPS API.
    Returns list of dicts: [{'t': '2025-10-15 02:30', 'v': '4.5', 'type': 'H'}, ...]
    """
    url = (
        f"https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?"
        f"date={date_str}&station={station_id}&product=predictions&datum=MLLW"
        f"&time_zone=lst_ldt&units=english&interval=hilo&application=WebServices&format=json"
    )
    try:
        # Create unverified context to avoid SSL cert issues in some envs
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        
        with urllib.request.urlopen(url, context=ctx, timeout=10) as response:
            data = json.loads(response.read().decode())
            return data.get('predictions', [])
    except Exception as e:
        logger.error(f"Failed to fetch NOAA data for {station_id}: {e}")
        return []

def parse_time(t_str):
    """Parse time string like '2025-10-15 02:30' or '02:30'."""
    # If full datetime
    try:
        return datetime.strptime(t_str, "%Y-%m-%d %H:%M")
    except ValueError:
        pass
    # If just time
    try:
        # Assume target date
        return datetime.strptime(f"2025-10-15 {t_str}", "%Y-%m-%d %H:%M")
    except ValueError:
        pass
    return None

def verify_station_data(user_data, truth_data, station_name):
    """
    Compare user data points against ground truth.
    Returns (score, feedback_lines)
    """
    if not user_data:
        return 0, [f"No data found for {station_name}"]
        
    if not truth_data:
        return 0, [f"Could not fetch ground truth for {station_name} (API error)"]

    # Normalize truth data: list of (datetime, value, type)
    truth_points = []
    for p in truth_data:
        dt = parse_time(p['t'])
        val = float(p['v'])
        ptype = p['type'] # 'H' or 'L'
        if dt:
            truth_points.append({'dt': dt, 'v': val, 'type': ptype})
            
    # Check match
    matches = 0
    feedback = []
    
    # We expect the user to find all High/Low events (usually 4)
    expected_count = len(truth_points)
    
    for u_pt in user_data:
        # User might use keys like "time", "height", "type"
        u_time_str = u_pt.get('time', '')
        u_height = u_pt.get('height_ft') or u_pt.get('height') or u_pt.get('v')
        
        if not u_time_str or u_height is None:
            continue
            
        u_dt = parse_time(u_time_str)
        if not u_dt:
            continue
            
        try:
            u_val = float(u_height)
        except:
            continue
            
        # Find closest match in truth
        best_match = None
        min_diff = float('inf')
        
        for t_pt in truth_points:
            diff = abs((t_pt['dt'] - u_dt).total_seconds())
            if diff < min_diff:
                min_diff = diff
                best_match = t_pt
                
        # Matching criteria: time +/- 10 mins, height +/- 0.5 ft
        if best_match and min_diff <= 600:
            if abs(best_match['v'] - u_val) <= 0.5:
                matches += 1
            else:
                feedback.append(f"{station_name}: Time matched {u_time_str} but height {u_val} != {best_match['v']}")
        else:
            feedback.append(f"{station_name}: No matching event for time {u_time_str}")

    score_pct = 0
    if expected_count > 0:
        score_pct = min(1.0, matches / expected_count)
        
    return score_pct * 25, feedback # 25 points max per station

def verify_noaa_tide_transit_planning(traj, env_info, task_info):
    """
    Verify NOAA Tide Transit Planning task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Copy result file
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name
    
    try:
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback = []

    # 1. Bookmarks (20 pts)
    folder_exists = result.get("folder_exists", 0)
    bm_count = result.get("bookmark_count", 0)
    has_battery = int(result.get("has_battery_bm", 0)) > 0
    has_kings = int(result.get("has_kings_bm", 0)) > 0
    
    if folder_exists:
        score += 5
        feedback.append("Bookmark folder created (+5)")
        if bm_count >= 2:
            score += 5
            feedback.append("At least 2 bookmarks in folder (+5)")
        if has_battery and has_kings:
            score += 10
            feedback.append("Correct station bookmarks found (+10)")
        elif has_battery or has_kings:
            score += 5
            feedback.append("One correct station bookmark found (+5)")
    else:
        feedback.append("Bookmark folder 'Project Alpha Logistics' not found")

    # 2. History (20 pts)
    visits = result.get("noaa_visits", 0)
    if visits >= 1:
        score += 20
        feedback.append(f"NOAA website visited ({visits} pages) (+20)")
    else:
        feedback.append("NOAA website not found in history")

    # 3. File existence (10 pts)
    if result.get("file_exists") and result.get("file_fresh"):
        score += 10
        feedback.append("Output file created (+10)")
    else:
        feedback.append("Output file missing or stale")

    # 4. Data Content (50 pts)
    file_content = result.get("file_content", {})
    if not isinstance(file_content, dict):
        feedback.append("Invalid JSON content")
    else:
        # Fetch ground truth
        truth_battery = fetch_noaa_predictions(STATION_BATTERY, TARGET_DATE)
        truth_kings = fetch_noaa_predictions(STATION_KINGS, TARGET_DATE)
        
        # Get user data
        stations_data = file_content.get("stations", {})
        
        # Find fuzzy keys for stations
        user_battery = []
        user_kings = []
        
        for k, v in stations_data.items():
            k_lower = k.lower()
            if "battery" in k_lower or "8518750" in k_lower:
                user_battery = v
            elif "king" in k_lower or "8516945" in k_lower:
                user_kings = v

        # Score Battery (25 pts)
        s_bat, fb_bat = verify_station_data(user_battery, truth_battery, "The Battery")
        score += s_bat
        if fb_bat: feedback.extend(fb_bat[:2]) # Limit feedback lines
        if s_bat == 25: feedback.append("Battery data correct (+25)")
        
        # Score Kings Point (25 pts)
        s_kp, fb_kp = verify_station_data(user_kings, truth_kings, "Kings Point")
        score += s_kp
        if fb_kp: feedback.extend(fb_kp[:2])
        if s_kp == 25: feedback.append("Kings Point data correct (+25)")

    return {
        "passed": score >= 60,
        "score": int(score),
        "feedback": "; ".join(feedback)
    }