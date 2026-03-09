#!/usr/bin/env python3
"""
Verifier for class_hierarchy_refactor task.
Checks schema evolution, data migration, and report generation.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_class_hierarchy_refactor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy unavailable"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Extract data
    db = data.get("db_state", {})
    expected = data.get("expected_counts", {})
    report = data.get("report_file", {})
    classes = db.get("classes", {})
    counts = db.get("counts", {})
    props = db.get("property_checks", {})

    # --- CRITERION 1: Schema Structure (25 pts) ---
    schema_score = 0
    # Check subclasses existence and inheritance
    for cls_name in ["BudgetHotels", "MidRangeHotels", "LuxuryHotels"]:
        cls_info = classes.get(cls_name)
        if cls_info and cls_info.get("exists"):
            if cls_info.get("superClass") == "Hotels":
                schema_score += 5
                feedback.append(f"Class {cls_name} extends Hotels correctly.")
            else:
                schema_score += 2
                feedback.append(f"Class {cls_name} exists but wrong superclass.")
        else:
            feedback.append(f"Class {cls_name} missing.")
            
    # Check 'Tier' property on Hotels
    if "Tier" in classes.get("Hotels", {}).get("properties", []):
        schema_score += 10
        feedback.append("Property Hotels.Tier exists.")
    else:
        feedback.append("Property Hotels.Tier missing.")
        
    score += schema_score

    # --- CRITERION 2: Data Migration (30 pts) ---
    migration_score = 0
    # Check that Hotels are moved out of the base class
    total_hotels = counts.get("Hotels_Total_Polymorphic", 0)
    base_hotels = counts.get("Hotels_Direct", 0)
    
    if total_hotels > 0 and base_hotels == 0:
        migration_score += 10
        feedback.append("All hotels migrated out of base class.")
    elif total_hotels > 0 and base_hotels < total_hotels:
        migration_score += 5
        feedback.append(f"Partial migration: {base_hotels} left in base class.")
    
    # Check specific subclass counts match expectations
    for tier, expected_key in [("Budget", "expected_budget"), ("MidRange", "expected_midrange"), ("Luxury", "expected_luxury")]:
        actual = counts.get(f"{tier}_Direct", 0)
        expect = expected.get(expected_key, -1)
        if expect > 0 and actual == expect:
            migration_score += 6.66
            feedback.append(f"{tier}Hotels count correct ({actual}).")
        elif expect > 0:
            feedback.append(f"{tier}Hotels count mismatch (Got {actual}, Expected {expect}).")
            
    score += int(migration_score)

    # --- CRITERION 3: Property Population (25 pts) ---
    prop_score = 0
    # Check Tier values
    tier_sum = props.get("Tier_Budget_Set", 0) + props.get("Tier_MidRange_Set", 0) + props.get("Tier_Luxury_Set", 0)
    if tier_sum >= total_hotels and total_hotels > 0:
        prop_score += 10
        feedback.append("Tier property populated for all records.")
    
    # Check Subclass specific booleans
    if props.get("Budget_Wifi_Set", 0) == counts.get("Budget_Direct", -1): prop_score += 5
    if props.get("MidRange_Pool_Set", 0) == counts.get("MidRange_Direct", -1): prop_score += 5
    if props.get("Luxury_Spa_Set", 0) == counts.get("Luxury_Direct", -1): prop_score += 5
    
    score += prop_score

    # --- CRITERION 4: Report File (20 pts) ---
    report_score = 0
    if report.get("exists"):
        report_score += 5
        content = ""
        try:
            content = base64.b64decode(report.get("content_b64", "")).decode().lower()
        except: pass
        
        # Check for keywords and counts in report
        if str(total_hotels) in content: report_score += 5
        if "luxury" in content: report_score += 5
        if "budget" in content: report_score += 5
        
        # Anti-gaming: Check report was created during task
        if report.get("mtime", 0) > data.get("task_start", 0):
            feedback.append("Report file created during task.")
        else:
            report_score = 0
            feedback.append("Report file is stale/pre-existing.")
    else:
        feedback.append("Report file not found.")
        
    score += report_score

    # Final Pass Determination
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }