#!/usr/bin/env python3
"""
Verifier for astronomy_observation_planning task.

Checks:
1. Firefox history contains visits to astronomy sites.
2. Bookmark folder 'Astronomy Tools' exists with bookmarks.
3. Output JSON file exists, is fresh, and contains accurate astronomical data for Tucson, Dec 13 2024.

Scoring (100 pts):
- File existence & freshness: 10 pts
- Valid JSON structure: 10 pts
- Bookmarks created: 15 pts
- History evidence: 5 pts
- Data Accuracy (Sunset/Twilight): 20 pts
- Data Accuracy (Moon Phase/Set): 20 pts
- Data Accuracy (Jupiter/ZHR): 20 pts
"""

import json
import os
import re
import datetime
import logging
import tempfile

logger = logging.getLogger(__name__)

def parse_time_str(time_str):
    """
    Parses various time formats (17:20, 5:20 PM) into a minutes-from-midnight integer.
    Returns None if parsing fails.
    """
    if not isinstance(time_str, str):
        return None
    
    time_str = time_str.lower().strip()
    
    # Try 24hr format HH:MM
    m24 = re.match(r'^(\d{1,2}):(\d{2})$', time_str)
    if m24:
        h, m = map(int, m24.groups())
        return h * 60 + m

    # Try 12hr format HH:MM am/pm
    m12 = re.match(r'^(\d{1,2}):(\d{2})\s*(am|pm)$', time_str)
    if m12:
        h, m, p = m12.groups()
        h = int(h)
        m = int(m)
        if p == 'pm' and h != 12:
            h += 12
        if p == 'am' and h == 12:
            h = 0
        return h * 60 + m
        
    return None

def check_time_range(actual_str, start_str, end_str, day_offset=0):
    """
    Checks if actual_str is between start_str and end_str.
    Handles times that might wrap around midnight if day_offset is involved, 
    but for this task, we mostly look at single-day events or explicitly next morning.
    """
    actual = parse_time_str(actual_str)
    start = parse_time_str(start_str)
    end = parse_time_str(end_str)
    
    if actual is None or start is None or end is None:
        return False, f"Could not parse times: {actual_str} vs {start_str}-{end_str}"
        
    # Handle wrapping if needed (e.g. 23:00 to 01:00), but simplified here:
    if start <= end:
        in_range = start <= actual <= end
    else:
        # Range crosses midnight (e.g. moon set next day)
        in_range = (start <= actual) or (actual <= end)
        
    return in_range, f"{actual_str} ({actual}) in {start_str}-{end_str}"

def verify_astronomy_observation_planning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Ground Truth from metadata
    gt = task_info.get('metadata', {}).get('ground_truth', {})
    
    # 1. Load Export Result
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load task_result.json: {e}")
        finally:
            try:
                os.unlink(f.name)
            except:
                pass

    # 2. Load User Plan
    user_plan = {}
    plan_loaded = False
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        try:
            copy_from_env("/tmp/stargazing_plan_submit.json", f.name)
            f.seek(0)
            user_plan = json.load(f)
            plan_loaded = True
        except Exception as e:
            logger.warning(f"Failed to load user plan: {e}")
        finally:
            try:
                os.unlink(f.name)
            except:
                pass

    score = 0
    feedback = []

    # Criteria 1: File Existence & Freshness (10 pts)
    if task_result.get('output_file_exists') and task_result.get('output_file_fresh'):
        score += 10
        feedback.append("Output file created during task.")
    else:
        feedback.append("Output file missing or stale.")

    # Criteria 2: Valid JSON Structure (10 pts)
    required_keys = ['sunset', 'astronomical_twilight_end', 'moon_illumination_percent', 'moon_set_time', 'jupiter_rise_time', 'geminids_zhr']
    if plan_loaded:
        missing_keys = [k for k in required_keys if k not in user_plan]
        if not missing_keys:
            score += 10
            feedback.append("JSON structure valid.")
        else:
            feedback.append(f"JSON missing keys: {missing_keys}")
    else:
        feedback.append("Could not load valid JSON.")

    # Criteria 3: Bookmarks (15 pts)
    if task_result.get('bookmark_folder_exists') and task_result.get('bookmark_count', 0) >= 2:
        score += 15
        feedback.append(f"Bookmarks verified ({task_result.get('bookmark_count')} in folder).")
    elif task_result.get('bookmark_folder_exists'):
        score += 5
        feedback.append("Bookmark folder found but fewer than 2 bookmarks.")
    else:
        feedback.append("Bookmark folder 'Astronomy Tools' not found.")

    # Criteria 4: History (5 pts)
    if task_result.get('astro_history_count', 0) > 0:
        score += 5
        feedback.append("Browsing history verified.")
    else:
        feedback.append("No history for astronomy sites found.")

    # Criteria 5, 6, 7: Data Accuracy (60 pts total)
    if plan_loaded:
        # Sun Data (20 pts)
        sun_score = 0
        s_ok, s_msg = check_time_range(str(user_plan.get('sunset', '')), gt.get('sunset_start', '17:15'), gt.get('sunset_end', '17:30'))
        t_ok, t_msg = check_time_range(str(user_plan.get('astronomical_twilight_end', '')), gt.get('twilight_end_start', '18:40'), gt.get('twilight_end_end', '19:00'))
        
        if s_ok: sun_score += 10
        else: feedback.append(f"Sunset mismatch: {s_msg}")
        if t_ok: sun_score += 10
        else: feedback.append(f"Twilight mismatch: {t_msg}")
        score += sun_score

        # Moon Data (20 pts)
        moon_score = 0
        illum = user_plan.get('moon_illumination_percent')
        try:
            # Handle "96%" or 96
            if isinstance(illum, str):
                illum = float(illum.replace('%', '').strip())
            
            if gt.get('moon_illum_min', 90) <= illum <= gt.get('moon_illum_max', 100):
                moon_score += 10
            else:
                feedback.append(f"Moon illum {illum}% out of range {gt.get('moon_illum_min')}-{gt.get('moon_illum_max')}%")
        except:
            feedback.append("Could not parse moon illumination.")

        ms_ok, ms_msg = check_time_range(str(user_plan.get('moon_set_time', '')), gt.get('moon_set_start', '05:00'), gt.get('moon_set_end', '06:00'))
        if ms_ok: moon_score += 10
        else: feedback.append(f"Moon set mismatch: {ms_msg}")
        score += moon_score

        # Planet/Meteor Data (20 pts)
        misc_score = 0
        j_ok, j_msg = check_time_range(str(user_plan.get('jupiter_rise_time', '')), gt.get('jupiter_rise_start', '16:20'), gt.get('jupiter_rise_end', '17:00'))
        if j_ok: misc_score += 10
        else: feedback.append(f"Jupiter rise mismatch: {j_msg}")

        zhr = user_plan.get('geminids_zhr')
        try:
            if isinstance(zhr, str):
                # Handle "120-150" by taking average or max, or just parsing first number
                zhr = float(re.search(r'\d+', zhr).group())
            
            if gt.get('zhr_min', 100) <= zhr <= gt.get('zhr_max', 200):
                misc_score += 10
            else:
                feedback.append(f"ZHR {zhr} out of range.")
        except:
            feedback.append("Could not parse ZHR.")
        score += misc_score
    else:
        feedback.append("Skipping data checks due to missing file.")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback)
    }