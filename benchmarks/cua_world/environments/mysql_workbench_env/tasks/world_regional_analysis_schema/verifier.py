#!/usr/bin/env python3
"""
Verifier for World Regional Analysis Schema task.

Scoring Criteria (100 points total):
1. Database Structure (45 pts)
   - DB exists (5)
   - Continents table correct (7 rows) (10)
   - Regions table populated & FK linked (10)
   - Country Stats populated & FK linked (20)
2. Logic & Automation (30 pts)
   - Audit table exists (5)
   - Trigger exists (5)
   - Trigger Logic Verified (Audit record exists for USA) (10)
   - Function exists (5)
   - Function returns correct value (5)
3. Data Export (25 pts)
   - CSV exists (10)
   - CSV created during task (5)
   - CSV has correct row count (10)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_world_regional_analysis(traj, env_info, task_info):
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

    # 1. Database Structure
    if result.get("db_exists", False):
        score += 5
        feedback.append("Database 'world_regions' created (5/5).")
    else:
        feedback.append("Database 'world_regions' NOT found.")

    if result.get("continents_correct_count", False):
        score += 10
        feedback.append("Continents table has correct 7 rows (10/10).")
    else:
        cnt = result.get("cnt_continents", 0)
        feedback.append(f"Continents table incorrect count: {cnt} (0/10).")

    # Regions (Must have rows and FK)
    regions_cnt = result.get("cnt_regions", 0)
    fk_regions = result.get("fk_regions_exists", 0)
    if regions_cnt >= 20 and int(fk_regions) > 0:
        score += 10
        feedback.append(f"Regions table populated ({regions_cnt} rows) and FK checked (10/10).")
    elif regions_cnt >= 20:
        score += 5
        feedback.append("Regions populated but FK missing (5/10).")
    else:
        feedback.append(f"Regions table empty or too few rows ({regions_cnt}) (0/10).")

    # Country Stats (Must have rows and FK)
    country_cnt = result.get("cnt_countries", 0)
    fk_countries = result.get("fk_countries_exists", 0)
    if country_cnt >= 230 and int(fk_countries) > 0:
        score += 20
        feedback.append(f"Country stats populated ({country_cnt} rows) and FK checked (20/20).")
    elif country_cnt >= 230:
        score += 10
        feedback.append("Country stats populated but FK missing (10/20).")
    else:
        feedback.append(f"Country stats empty or too few rows ({country_cnt}) (0/20).")

    # 2. Logic & Automation
    # Audit Table & Trigger
    # (We infer audit table existence if audit_record_count is checked, but explicitly:
    # The export script checks info schema for audit table, but didn't output explicit bool,
    # however, audit_record_count > 0 implies table exists)
    
    # Trigger Existence
    if int(result.get("has_trigger", 0)) > 0:
        score += 5
        feedback.append("Trigger created (5/5).")
        # Trigger Logic (Audit record for USA)
        if int(result.get("audit_record_count", 0)) > 0:
            score += 10 + 5 # 5 pts for table existing (implied), 10 for logic
            feedback.append("Audit table exists and trigger fired correctly for USA (15/15).")
        else:
             # If table exists but no record, maybe partial credit if we could detect table
             # Simplification: if trigger exists but didn't fire, 0 for logic.
             # We give 5 pts for table existence if we can infer it was created?
             # Let's be strict: no audit record = logic fail.
             feedback.append("Trigger exists but did not log USA update (0/15).")
    else:
        feedback.append("Trigger not created (0/20).")

    # Function
    if int(result.get("has_function", 0)) > 0:
        score += 5
        feedback.append("Stored function created (5/5).")
        
        # Check Result (Europe Avg Life Expectancy is approx 75-80 in World DB)
        try:
            val = float(result.get("function_result_europe", 0))
            if 65.0 <= val <= 85.0:
                score += 5
                feedback.append(f"Function returned valid result: {val} (5/5).")
            else:
                feedback.append(f"Function returned unexpected value: {val} (0/5).")
        except:
            feedback.append("Function return value invalid (0/5).")
    else:
        feedback.append("Stored function not created (0/10).")

    # 3. Data Export
    csv_exists = result.get("csv_exists", False)
    csv_fresh = result.get("csv_fresh", False)
    csv_rows = int(result.get("csv_rows", 0))

    if csv_exists:
        score += 10
        if csv_fresh:
            score += 5
        else:
            feedback.append("CSV file timestamp too old (0/5).")
        
        if 18 <= csv_rows <= 22: # Expected 20, allow small tolerance
            score += 10
            feedback.append(f"CSV row count correct: {csv_rows} (10/10).")
        else:
            feedback.append(f"CSV row count incorrect: {csv_rows} (expected ~20) (0/10).")
    else:
        feedback.append("CSV export not found (0/25).")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }