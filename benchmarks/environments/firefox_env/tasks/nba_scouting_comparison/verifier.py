#!/usr/bin/env python3
"""
Verifier for nba_scouting_comparison task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nba_scouting_comparison(traj, env_info, task_info):
    """
    Verifies the NBA Scouting Comparison task.
    
    Scoring Criteria (100 points total):
    1. Output file exists and is valid JSON (10 pts)
    2. Output file was created during the task (5 pts)
    3. JSON contains all 3 required players (15 pts)
    4. JSON structure is correct (5 fields per player) (10 pts)
    5. Data plausibility for LeBron James (10 pts)
    6. Data plausibility for Stephen Curry (10 pts)
    7. Data plausibility for Nikola Jokic (10 pts)
    8. Browser history shows basketball-reference.com visits (10 pts)
    9. "NBA Scouting" bookmark folder exists (10 pts)
    10. Bookmark folder contains >= 3 bookmarks (10 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    player_ranges = metadata.get('players', {})
    
    # 2. Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/nba_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result file"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 3. Verify File Existence & Validity (15 pts)
    file_content = result.get("file_content", {})
    if result.get("file_exists") and file_content:
        score += 10
        feedback.append("JSON file exists and is valid.")
    else:
        feedback.append("JSON file missing or invalid.")
        
    if result.get("file_fresh"):
        score += 5
        feedback.append("File created during task.")
    else:
        feedback.append("File not created during task (stale or missing).")

    # 4. Verify Content (Keys & Structure) (25 pts)
    # Normalize keys to lower case for loose matching
    content_lower = {k.lower(): v for k, v in file_content.items() if isinstance(v, dict)}
    
    required_players = ["lebron", "curry", "jokic"]
    found_players = []
    for req in required_players:
        for key in content_lower:
            if req in key:
                found_players.append(key)
                break
    
    if len(found_players) == 3:
        score += 15
        feedback.append("All 3 required players found in JSON.")
    else:
        feedback.append(f"Found {len(found_players)}/3 players.")

    # Check structure (fields)
    required_fields = ["ppg", "apg", "rpg", "seasons", "championships"]
    fields_ok = True
    for p_key in found_players:
        p_data = content_lower[p_key]
        # Allow case-insensitive field matching
        p_data_lower = {k.lower(): v for k, v in p_data.items()}
        for field in required_fields:
            if field not in p_data_lower:
                fields_ok = False
                break
    
    if len(found_players) > 0 and fields_ok:
        score += 10
        feedback.append("JSON structure contains all required fields.")
    elif len(found_players) > 0:
        feedback.append("JSON structure missing some required fields.")

    # 5. Verify Data Plausibility (30 pts)
    # Helper to check a single player
    def check_player(name_key, range_key):
        # Find the actual key in content_lower
        p_key = next((k for k in content_lower if name_key in k), None)
        if not p_key: return 0, f"{name_key} not found"
        
        data = content_lower[p_key]
        # Normalize data keys
        data = {k.lower(): v for k, v in data.items()}
        ranges = player_ranges.get(range_key, {})
        
        checks = 0
        total_checks = 5
        
        try:
            if ranges["ppg_range"][0] <= float(data.get("ppg", 0)) <= ranges["ppg_range"][1]: checks += 1
            if ranges["apg_range"][0] <= float(data.get("apg", 0)) <= ranges["apg_range"][1]: checks += 1
            if ranges["rpg_range"][0] <= float(data.get("rpg", 0)) <= ranges["rpg_range"][1]: checks += 1
            if ranges["seasons_range"][0] <= int(data.get("seasons", 0)) <= ranges["seasons_range"][1]: checks += 1
            # Exact or close match for championships
            champ = int(data.get("championships", -1))
            if ranges["championships_range"][0] <= champ <= ranges["championships_range"][1]: checks += 1
        except (ValueError, TypeError):
            return 0, f"{name_key}: Invalid data types"

        # Allow 1 mistake per player for full credit, or partial credit
        if checks >= 4: return 10, f"{name_key} data plausible"
        if checks >= 2: return 5, f"{name_key} data partially correct"
        return 0, f"{name_key} data incorrect"

    s_lbj, f_lbj = check_player("lebron", "lebron_james")
    s_curry, f_curry = check_player("curry", "stephen_curry")
    s_jokic, f_jokic = check_player("jokic", "nikola_jokic")
    
    score += s_lbj + s_curry + s_jokic
    feedback.append(f"Stats: {f_lbj}, {f_curry}, {f_jokic}")

    # 6. Verify Browser History (10 pts)
    if result.get("history_count", 0) > 0:
        score += 10
        feedback.append("Browser history confirms research on correct site.")
    else:
        feedback.append("No browser history found for target domain.")

    # 7. Verify Bookmarks (20 pts)
    if result.get("bookmark_folder_exists"):
        score += 10
        feedback.append("'NBA Scouting' bookmark folder exists.")
        
        count = result.get("bookmark_count", 0)
        if count >= 3:
            score += 10
            feedback.append(f"Found {count} bookmarks in folder (>=3).")
        else:
            feedback.append(f"Found only {count} bookmarks in folder (need 3).")
    else:
        feedback.append("'NBA Scouting' bookmark folder missing.")

    # Final Pass Determination
    # Pass if score >= 60 AND file exists/valid
    passed = (score >= 60) and (result.get("file_exists") and file_content)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }