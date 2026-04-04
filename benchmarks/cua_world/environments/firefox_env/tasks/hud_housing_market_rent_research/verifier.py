#!/usr/bin/env python3
"""
Verifier for HUD FMR Research Task.
Verifies JSON output accuracy and Firefox browser evidence.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hud_housing_market_rent_research(traj, env_info, task_info):
    """
    Verify HUD FMR research task.
    
    Criteria:
    1. JSON file exists and is valid (10 pts)
    2. Fiscal Year is 2024 (15 pts)
    3. Keys for all 3 counties exist (15 pts)
    4. Rent values are within plausible ranges (30 pts)
    5. Bookmarks created correctly (15 pts)
    6. HUD website visited (15 pts)
    """
    
    # 1. Setup copy from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get result file
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
    
    # --- Criterion 1: JSON File Exists & Valid (10 pts) ---
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found at ~/Documents/fmr_audit_2024.json"}
    
    try:
        raw_content = result.get("file_content_raw", "")
        if not raw_content:
             return {"passed": False, "score": 0, "feedback": "Output file is empty"}
        
        data = json.loads(raw_content)
        score += 10
        feedback.append("JSON file exists and is valid (+10)")
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Output file is not valid JSON"}

    # --- Criterion 2: Fiscal Year 2024 (15 pts) ---
    # Allow string "2024" or int 2024
    fy = str(data.get("fiscal_year", "")).strip()
    if "2024" in fy:
        score += 15
        feedback.append("Correct fiscal year 2024 (+15)")
    else:
        feedback.append(f"Incorrect fiscal year: {fy} (Expected 2024)")

    # --- Criterion 3: Structure Check (15 pts) ---
    required_keys = ["miami_dade_fl", "king_wa", "suffolk_ma"]
    missing_keys = [k for k in required_keys if k not in data]
    
    if not missing_keys:
        score += 15
        feedback.append("All required location keys present (+15)")
    else:
        feedback.append(f"Missing keys: {missing_keys}")

    # --- Criterion 4: Value Plausibility (30 pts) ---
    # Ranges defined in metadata or defaults here
    # 2024 FMR estimates:
    # Miami: Eff ~$1700, 1BR ~$1800, 2BR ~$2300
    # King (Seattle): Eff ~$2100, 1BR ~$2200, 2BR ~$2600
    # Suffolk (Boston): Eff ~$2200, 1BR ~$2400, 2BR ~$2800
    
    # We use generous ranges to account for slight data interpretation differences 
    # (e.g. Metro area vs specific zip code if agent gets confused, though task asks for County/Metro)
    ranges = {
        "miami_dade_fl": {"eff_min": 1000, "2br_min": 1500},
        "king_wa": {"eff_min": 1500, "2br_min": 1800},
        "suffolk_ma": {"eff_min": 1500, "2br_min": 2000}
    }
    
    value_points = 0
    max_value_points = 30
    plausible_count = 0
    total_checks = 0
    
    for loc, criteria in ranges.items():
        if loc in data and isinstance(data[loc], dict):
            entry = data[loc]
            # Check if values are numbers and look reasonable (not 0)
            eff = entry.get("efficiency", 0)
            br2 = entry.get("two_bedroom", 0)
            
            try:
                eff = float(str(eff).replace("$", "").replace(",", ""))
                br2 = float(str(br2).replace("$", "").replace(",", ""))
                
                if eff > criteria["eff_min"]:
                    plausible_count += 1
                if br2 > criteria["2br_min"]:
                    plausible_count += 1
            except:
                pass
            total_checks += 2
            
    if total_checks > 0:
        value_ratio = plausible_count / total_checks
        points_earned = int(value_ratio * max_value_points)
        score += points_earned
        if points_earned == max_value_points:
            feedback.append("Rent values look plausible (+30)")
        else:
            feedback.append(f"Some rent values seem too low or invalid ({points_earned}/30)")
    else:
        feedback.append("Could not verify rent values structure")

    # --- Criterion 5: Bookmarks (15 pts) ---
    bm_folder_exists = result.get("bookmark_folder_exists", False)
    hud_bm_count = result.get("hud_bookmarks_count", 0)
    
    if bm_folder_exists:
        if hud_bm_count >= 3:
            score += 15
            feedback.append("'HUD FMR Audit' folder exists with 3+ HUD bookmarks (+15)")
        elif hud_bm_count >= 1:
            score += 10
            feedback.append("'HUD FMR Audit' folder exists but fewer than 3 HUD bookmarks (+10)")
        else:
            score += 5
            feedback.append("'HUD FMR Audit' folder exists but empty/wrong links (+5)")
    else:
        feedback.append("'HUD FMR Audit' bookmark folder not found")

    # --- Criterion 6: History (15 pts) ---
    history_count = result.get("hud_history_count", 0)
    if history_count > 0:
        score += 15
        feedback.append("HUD User website history verified (+15)")
    else:
        feedback.append("No history of visiting huduser.gov found")

    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }