#!/usr/bin/env python3
"""
Verifier for airport_facility_data_collection@1

Scoring System (100 points):
1. History Evidence (10 pts): Visits to AirNav.
2. Bookmark Organization (15 pts): 'Mountain Airports' folder with >= 3 bookmarks.
3. Chart Download (20 pts): Valid PDF download of KASE approach plate.
4. JSON File Existence (15 pts): Valid JSON file created.
5. Data Accuracy (40 pts): Checks KASE, KTEX, KEGE data against ground truth.

"""

import json
import os
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def clean_string(s):
    """Normalize string for comparison (lowercase, remove spaces)."""
    if not isinstance(s, str):
        return str(s)
    return s.lower().replace(" ", "").replace(",", "").replace("-", "")

def check_range(val, min_val, max_val):
    """Check if value is within range, handling string inputs."""
    try:
        # Extract numbers from string like "7,820 ft"
        if isinstance(val, str):
            nums = re.findall(r"[\d\.]+", val.replace(",", ""))
            if nums:
                val = float(nums[0])
            else:
                return False
        return min_val <= float(val) <= max_val
    except:
        return False

def verify_airport_data(traj, env_info, task_info):
    """Verify the airport data collection task."""
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # Load ground truth from metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})

    # 2. Get Export Results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Get User JSON Content
    user_json_data = {}
    if export_data.get('json_exists', False):
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(export_data['json_path'], temp_json.name)
            with open(temp_json.name, 'r') as f:
                user_json_data = json.load(f)
        except Exception:
            logger.warning("Failed to copy/parse user JSON file")
        finally:
            if os.path.exists(temp_json.name):
                os.unlink(temp_json.name)

    # 4. Scoring
    score = 0
    feedback = []

    # Criterion 1: History (10 pts)
    if export_data.get('airnav_history_count', 0) >= 3:
        score += 10
        feedback.append("History: Good AirNav usage detected (+10)")
    elif export_data.get('airnav_history_count', 0) > 0:
        score += 5
        feedback.append("History: Partial AirNav usage detected (+5)")
    else:
        feedback.append("History: No AirNav visits found")

    # Criterion 2: Bookmarks (15 pts)
    if export_data.get('bookmark_folder_exists', False):
        count = export_data.get('bookmark_count', 0)
        if count >= 3:
            score += 15
            feedback.append(f"Bookmarks: Folder 'Mountain Airports' found with {count} items (+15)")
        else:
            score += 10
            feedback.append(f"Bookmarks: Folder found but only {count}/3 items (+10)")
    else:
        feedback.append("Bookmarks: 'Mountain Airports' folder not found")

    # Criterion 3: PDF Download (20 pts)
    if export_data.get('pdf_downloaded', False):
        filename = export_data.get('pdf_filename', '').lower()
        if 'loc' in filename or 'dme' in filename or 'kase' in filename:
            score += 20
            feedback.append(f"Download: Relevant PDF found ({filename}) (+20)")
        else:
            score += 10
            feedback.append(f"Download: PDF found but filename unsure ({filename}) (+10)")
    else:
        feedback.append("Download: No PDF found in Downloads")

    # Criterion 4: JSON Existence (15 pts)
    if export_data.get('json_exists', False) and user_json_data:
        score += 15
        feedback.append("JSON: File exists and is valid (+15)")
    else:
        feedback.append("JSON: File missing or invalid")

    # Criterion 5: Data Accuracy (40 pts)
    # Check KASE, KTEX, KEGE
    airports_data = user_json_data.get('airports', {})
    
    for code in ['KASE', 'KTEX', 'KEGE']:
        if code not in airports_data:
            feedback.append(f"Data: Missing {code} entry")
            continue
            
        gt = ground_truth.get(code, {})
        usr = airports_data[code]
        
        # Points per airport: ~13 pts total (4 pts elev, 4 pts rwy, 5 pts freq/artcc)
        
        # Elevation
        if check_range(usr.get('elevation_ft', 0), gt['elevation_min'], gt['elevation_max']):
            score += 4
        else:
            feedback.append(f"Data {code}: Elevation mismatch")
            
        # Runway
        if check_range(usr.get('longest_runway', 0), gt['runway_len_min'], gt['runway_len_max']):
            score += 4
        else:
            feedback.append(f"Data {code}: Runway length mismatch")
            
        # Frequency
        usr_freq = str(usr.get('frequency_mhz', '')).replace(" ", "")
        if any(f in usr_freq for f in gt['freq_primary']):
            score += 3
        else:
            feedback.append(f"Data {code}: Frequency mismatch")
            
        # ARTCC
        if clean_string(usr.get('artcc', '')) == clean_string(gt['artcc']):
            score += 2
            
    # Normalize score to 100 max (calculation above is slightly >40 for data)
    # 10 + 15 + 20 + 15 + (3 airports * 13) = 60 + 39 = 99. Close enough to 100.
    # Let's verify sum: 4+4+3+2 = 13 per airport. 13*3 = 39. Total = 99.
    # We can add 1 bonus point if everything is perfect.
    
    if score >= 99:
        score = 100

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": "; ".join(feedback)
    }