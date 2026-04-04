#!/usr/bin/env python3
"""
Verifier for energystar_appliance_procurement task.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_energystar_procurement(traj, env_info, task_info):
    """
    Verifies the Energy Star procurement task.
    """
    # 1. Setup & Copy Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    json_exists = result.get('json_exists', False)
    json_valid = result.get('json_valid', False)
    json_content = result.get('json_content', [])
    download_found = result.get('download_found', False)
    bookmark_folder = result.get('bookmark_folder_found', False)
    bookmark_count = result.get('bookmark_count', 0)
    url_visited = result.get('url_visited', False)

    score = 0
    feedback = []

    # 3. Scoring Criteria

    # Criterion A: Navigation (10 pts)
    if url_visited:
        score += 10
        feedback.append("Visits to energystar.gov detected.")
    else:
        feedback.append("No history of visiting energystar.gov.")

    # Criterion B: Export File (20 pts)
    if download_found:
        score += 20
        feedback.append(f"Export file found: {result.get('download_filename')}.")
    else:
        feedback.append("No exported Excel/CSV file found in Downloads (created during task).")

    # Criterion C: Bookmark (20 pts)
    if bookmark_folder:
        score += 10
        feedback.append("Bookmark folder 'Appliance Procurement' found.")
        if bookmark_count > 0:
            score += 10
            feedback.append(f"Folder contains {bookmark_count} bookmarks.")
        else:
            feedback.append("Bookmark folder is empty.")
    else:
        feedback.append("Bookmark folder 'Appliance Procurement' not found.")

    # Criterion D: JSON Output (50 pts total)
    if not json_exists:
        feedback.append("Selection JSON file not created.")
    elif not json_valid:
        feedback.append("Selection file exists but is not valid JSON.")
    else:
        # JSON Structure & Content Check
        score += 10 # File exists and is valid JSON
        
        if isinstance(json_content, list) and len(json_content) == 3:
            score += 10
            feedback.append("JSON contains exactly 3 entries.")
            
            # Check values
            valid_entries = 0
            sorted_correctly = True
            prev_kwh = -1
            
            for entry in json_content:
                kwh = entry.get('annual_energy_use_kwh', 0)
                model = entry.get('model_number', '')
                
                # Plausibility check: Top freezers 16-19cuft are usually 250-450 kWh
                # We use a broad range (200-500) to account for variations
                if isinstance(kwh, (int, float)) and 200 <= kwh <= 500 and model:
                    valid_entries += 1
                
                # Check sorting (Low to High)
                if prev_kwh != -1 and kwh < prev_kwh:
                    sorted_correctly = False
                prev_kwh = kwh
            
            if valid_entries == 3:
                score += 20
                feedback.append("All 3 entries have plausible kWh values (200-500) and model numbers.")
            else:
                feedback.append(f"Only {valid_entries}/3 entries seem plausible/complete.")

            if sorted_correctly and valid_entries == 3:
                score += 10
                feedback.append("Entries appear correctly sorted by energy use (Low to High).")
            elif not sorted_correctly:
                feedback.append("Entries are NOT sorted Low to High as requested.")
        else:
            feedback.append(f"JSON should be a list of 3 items, found: {type(json_content)} of len {len(json_content) if isinstance(json_content, list) else 0}.")

    # 4. Final Verification
    # Threshold: Need 60 points + Valid JSON content implies core task understanding
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }