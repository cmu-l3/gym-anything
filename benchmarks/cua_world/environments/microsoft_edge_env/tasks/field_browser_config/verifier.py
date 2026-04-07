#!/usr/bin/env python3
"""
Verifier for Field Browser Config task.
Verifies Edge settings, saved files, bookmarks, and documentation.
"""

import json
import logging
import os
import tempfile
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_field_config(traj, env_info, task_info):
    """
    Verify the configuration of Edge for field operations.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dl_dir = metadata.get('field_data_dir', '/home/ga/Documents/FieldData')
    
    # Retrieve result file
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
    
    # --- Check 1: Preferences (35 points) ---
    prefs = result.get('preferences', {})
    
    # 1a. Download Directory (10 pts)
    actual_dl_dir = prefs.get('download_dir', '')
    if actual_dl_dir == expected_dl_dir:
        score += 10
        feedback.append("Download directory configured correctly.")
    else:
        feedback.append(f"Download directory incorrect. Expected '{expected_dl_dir}', got '{actual_dl_dir}'.")

    # 1b. Home Button (10 pts)
    show_home = prefs.get('show_home_button', False)
    homepage = prefs.get('homepage', '')
    if show_home and 'weather.gov' in homepage:
        score += 10
        feedback.append("Home button configured correctly.")
    else:
        feedback.append(f"Home button config failed. Show: {show_home}, URL: {homepage}")

    # 1c. Startup Pages (15 pts)
    # startup_type 4 means "Open specific pages"
    startup_type = prefs.get('startup_type', 0)
    startup_urls = prefs.get('startup_urls', [])
    
    has_osha = any('osha.gov' in u for u in startup_urls)
    has_weather = any('weather.gov' in u for u in startup_urls)
    
    if startup_type == 4 and has_osha and has_weather:
        score += 15
        feedback.append("Startup pages configured correctly.")
    elif startup_type == 4 and (has_osha or has_weather):
        score += 7
        feedback.append("Startup pages partially correct (missing one URL).")
    else:
        feedback.append(f"Startup pages incorrect. Type: {startup_type}, URLs: {startup_urls}")

    # --- Check 2: Saved Files (25 points) ---
    files_info = result.get('files', {})
    file_count = files_info.get('count', 0)
    file_details_str = files_info.get('details', '')
    task_start_time = result.get('task_start', 0)

    # Parse details to check size and timestamps
    valid_files = 0
    for line in file_details_str.strip().split('\n'):
        if not line: continue
        try:
            name, size, mtime = line.split('|')
            # Check size (>5KB to ensure it's not empty/stub) and time
            if int(size) > 5000 and float(mtime) > task_start_time:
                valid_files += 1
        except:
            pass

    if valid_files >= 3:
        score += 25
        feedback.append(f"All 3 reference pages saved successfully ({valid_files} valid files).")
    elif valid_files >= 1:
        score += 10
        feedback.append(f"Only {valid_files}/3 pages saved correctly.")
    else:
        feedback.append("No valid saved pages found (check directory, size > 5KB, and timestamp).")

    # --- Check 3: Bookmarks (20 points) ---
    bookmarks = result.get('bookmarks', {})
    if bookmarks.get('exists'):
        children = bookmarks.get('children', [])
        bk_osha_c = any('osha.gov/construction' in u for u in children)
        bk_osha_f = any('osha.gov/fall-protection' in u for u in children)
        bk_weather = any('weather.gov' in u for u in children)
        
        count = sum([bk_osha_c, bk_osha_f, bk_weather])
        if count >= 3:
            score += 20
            feedback.append("Bookmark folder created with all required links.")
        elif count >= 1:
            score += 10
            feedback.append(f"Bookmark folder exists but missing some links (found {count}/3).")
        else:
            score += 5
            feedback.append("Bookmark folder 'Field Resources' exists but is empty.")
    else:
        feedback.append("Bookmark folder 'Field Resources' not found.")

    # --- Check 4: Documentation (10 points) ---
    report = result.get('report', {})
    if report.get('exists'):
        content = report.get('content_preview', '').lower()
        required_terms = ['osha', 'weather', 'field']
        if any(term in content for term in required_terms):
            score += 10
            feedback.append("Configuration summary report exists and looks valid.")
        else:
            score += 5
            feedback.append("Report exists but missing specific keywords.")
    else:
        feedback.append("Configuration summary report missing.")

    # --- Check 5: History (10 points) ---
    # Anti-gaming: Ensure they actually visited the sites, not just created files/prefs manually
    history_urls = result.get('history_urls', [])
    visited_osha = any('osha.gov' in u for u in history_urls)
    visited_weather = any('weather.gov' in u for u in history_urls)
    
    if visited_osha and visited_weather:
        score += 10
        feedback.append("Browser history confirms visits to target sites.")
    elif visited_osha or visited_weather:
        score += 5
        feedback.append("Browser history shows partial visits.")
    else:
        feedback.append("No history of visiting target sites found.")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }