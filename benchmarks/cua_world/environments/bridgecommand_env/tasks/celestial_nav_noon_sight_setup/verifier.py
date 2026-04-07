#!/usr/bin/env python3
import json
import os
import re
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_celestial_nav_noon_sight_setup(traj, env_info, task_info):
    """
    Verify the Celestial Navigation Noon Sight Setup task.
    
    Verifies:
    1. Scenario creation (files exist)
    2. Geographic Position (45N, 10W)
    3. Date (June 15)
    4. Time Calculation:
       - 10W = +40 mins from Greenwich (LAN is later).
       - Eq of Time June 15 ~ 0m.
       - Expected LAN ~ 12:40 UTC.
       - Task requires start 20 mins before -> 12:20 UTC.
       - Bridge Command uses decimal hours: 12:20 -> 12.33.
    5. Altitude Calculation (Briefing):
       - Dec June 15 ~ 23.3 N.
       - Lat 45 N.
       - Alt = 90 - (45 - 23.3) = 68.3 degrees.
    """
    
    # 1. Setup & Read Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # --- Criterion 1: Structure (10 pts) ---
    if result.get('scenario_exists') and result.get('env_ini_exists') and result.get('ownship_ini_exists'):
        score += 10
        feedback.append("Scenario directory and INI files created.")
    else:
        feedback.append("Missing scenario directory or INI files.")

    config = result.get('config', {})
    
    # --- Criterion 2: Position (10 pts) ---
    try:
        lat = float(config.get('lat', -999))
        lon = float(config.get('long', -999))
        
        # Target: 45N (+45), 10W (-10)
        # Note: Bridge Command longitude: East is positive usually, check convention.
        # Even if sign is flipped, we check magnitude, but usually W is negative.
        if abs(lat - 45.0) < 0.1 and abs(lon - (-10.0)) < 0.1:
            score += 10
            feedback.append("Position correct (45N, 10W).")
        else:
            feedback.append(f"Position incorrect. Found Lat: {lat}, Long: {lon}. Expected 45.0, -10.0.")
    except:
        feedback.append("Could not parse position coordinates.")

    # --- Criterion 3: Date (10 pts) ---
    # June 15
    try:
        month = int(config.get('start_month', 0))
        day = int(config.get('start_day', 0))
        
        if month == 6 and day == 15:
            score += 10
            feedback.append("Date correct (June 15).")
        else:
            feedback.append(f"Date incorrect. Found {month}/{day}. Expected 6/15.")
    except:
        feedback.append("Could not parse date.")

    # --- Criterion 4: Start Time Calculation (35 pts) ---
    # Target LAN: 12:40 UTC (12.66 hours)
    # Target Start: 20 mins before -> 12:20 UTC (12.33 hours)
    # Tolerance: +/- 5 minutes (+/- 0.08 hours)
    
    target_start_decimal = 12.333
    tolerance = 0.08 # ~5 mins
    
    try:
        start_time_val = float(config.get('start_time_decimal', -1))
        
        if abs(start_time_val - target_start_decimal) <= tolerance:
            score += 35
            feedback.append(f"Start Time correct ({start_time_val:.2f}h / ~12:20 UTC).")
        else:
            # Partial credit if they set it to exactly Noon (12.0) or LAN (12.66) without offset
            if abs(start_time_val - 12.0) < 0.05:
                score += 10
                feedback.append("Start Time set to 12:00, missed the longitude calculation or offset.")
            elif abs(start_time_val - 12.66) < 0.05:
                score += 15
                feedback.append("Start Time set to LAN exactly, missed the '20 mins before' instruction.")
            else:
                feedback.append(f"Start Time incorrect: {start_time_val:.2f}. Expected ~12.33 (12:20 UTC).")
    except:
        feedback.append("Could not parse StartTime.")

    # --- Criterion 5: Altitude Calculation in Briefing (25 pts) ---
    # Target Altitude: ~68.3 degrees
    # Search for numbers close to 68.3 in the briefing text
    
    briefing_text = result.get('briefing_content', "")
    if result.get('briefing_exists'):
        score += 5 # 5 points just for file existing
        
        # Regex to find numbers like 68.3, 68, 68 deg, etc.
        # We look for numbers between 67 and 70.
        found_alt = False
        numbers = re.findall(r"(\d+\.?\d*)", briefing_text)
        
        best_alt_diff = 999
        best_alt_val = 0
        
        for num_str in numbers:
            try:
                val = float(num_str)
                # Ignore numbers that look like dates (15, 2025) or times (12.33)
                if 60.0 < val < 75.0:
                    diff = abs(val - 68.3)
                    if diff < best_alt_diff:
                        best_alt_diff = diff
                        best_alt_val = val
            except:
                pass
        
        if best_alt_diff <= 0.5:
            score += 20
            feedback.append(f"Briefing contains correct Meridian Altitude ({best_alt_val}).")
            found_alt = True
        elif best_alt_diff <= 2.0:
             score += 10
             feedback.append(f"Briefing contains approximate Altitude ({best_alt_val}). Target was 68.3.")
        else:
            feedback.append("Briefing does not contain a correct Meridian Altitude (expected ~68.3).")
            
        # Check for LAN time mention in briefing (12:40 or 12.66)
        if "12:40" in briefing_text or "12.6" in briefing_text or "12.7" in briefing_text:
             score += 10
             feedback.append("Briefing mentions correct LAN time.")
        else:
             feedback.append("Briefing does not clearly mention the calculated LAN time (12:40).")
             
    else:
        feedback.append("Briefing file not created.")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " ".join(feedback)
    }