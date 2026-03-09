#!/usr/bin/env python3
"""
Verifier for ev_fleet_procurement_research task.

Scoring:
- History visits to fueleconomy.gov (20 pts)
- Bookmark folder 'EV Fleet Candidates' created with >=3 links (15 pts)
- Report file exists and is valid JSON (15 pts)
- Data Accuracy (50 pts total):
    - Range checks for 3 vehicles (20 pts)
    - Savings > 1000 (15 pts)
    - Tax credit info present (15 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ev_fleet_procurement_research(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. History Check (20 pts)
    visits = result.get("history_visits", 0)
    if visits >= 3:
        score += 20
        feedback.append("History: Visited fueleconomy.gov (20/20)")
    elif visits > 0:
        score += 10
        feedback.append("History: Visited site but few pages (10/20)")
    else:
        feedback.append("History: No visits to fueleconomy.gov (0/20)")

    # 2. Bookmark Check (15 pts)
    folder_exists = result.get("bookmark_folder_exists", False)
    bm_count = result.get("bookmark_count", 0)
    if folder_exists:
        if bm_count >= 3:
            score += 15
            feedback.append(f"Bookmarks: Folder created with {bm_count} items (15/15)")
        else:
            score += 10
            feedback.append(f"Bookmarks: Folder created but only {bm_count} items (10/15)")
    else:
        feedback.append("Bookmarks: 'EV Fleet Candidates' folder not found (0/15)")

    # 3. Report Existence & Structure (15 pts)
    report_exists = result.get("report_exists", False)
    report_fresh = result.get("report_fresh", False)
    report_data = result.get("report_content", {})

    if report_exists and report_fresh:
        if isinstance(report_data, dict) and "vehicles" in report_data:
            score += 15
            feedback.append("Report: Exists, fresh, and valid structure (15/15)")
            vehicles = report_data["vehicles"]
        elif isinstance(report_data, dict) and "tesla_model_3_lr" in report_data:
             # Handle flat structure if agent didn't nest under "vehicles"
            score += 10
            feedback.append("Report: Valid JSON but flat structure (10/15)")
            vehicles = report_data
        else:
            score += 5
            feedback.append("Report: Invalid structure (5/15)")
            vehicles = {}
    else:
        feedback.append("Report: Missing or not created during task (0/15)")
        vehicles = {}

    # 4. Data Accuracy (50 pts)
    # Define expected ranges (broad tolerance for model year/trim diffs)
    # Tesla Model 3 LR: ~341 (Allow 320-360)
    # Ioniq 5 AWD: ~260 (Allow 240-280)
    # F-150 Lightning Ext: ~320 (Allow 300-340)
    
    range_score = 0
    savings_score = 0
    credit_score = 0

    expected = {
        "tesla_model_3_lr": (320, 360),
        "hyundai_ioniq_5_awd": (240, 280),
        "ford_lightning_ext": (300, 340)
    }

    # Helper to sanitize currency strings to ints
    def parse_money(val):
        if isinstance(val, (int, float)): return val
        if isinstance(val, str):
            clean = ''.join(c for c in val if c.isdigit() or c == '.')
            return float(clean) if clean else 0
        return 0

    valid_vehicles_count = 0
    
    for key, (min_r, max_r) in expected.items():
        v_data = vehicles.get(key, {})
        if not v_data: continue
        valid_vehicles_count += 1
        
        # Check Range
        r_val = v_data.get("epa_range_miles", 0)
        if isinstance(r_val, (int, float)) and min_r <= r_val <= max_r:
            range_score += 6.6 # ~20 pts total
        
        # Check Savings (Dynamic, just check > 1000 and positive)
        s_val = parse_money(v_data.get("five_year_savings_usd", 0))
        if s_val > 1000:
            savings_score += 5 # 15 pts total
            
        # Check Credit (Just check presence)
        c_val = v_data.get("tax_credit_amount", "")
        if c_val or v_data.get("tax_credit_eligible") is not None:
            credit_score += 5 # 15 pts total

    score += int(range_score + savings_score + credit_score)
    feedback.append(f"Data Accuracy: Range({int(range_score)}/20), Savings({int(savings_score)}/15), Credits({int(credit_score)}/15)")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }