#!/usr/bin/env python3
"""
Verifier for federal_pay_research task.
Validates:
1. JSON report content (pay tables, benefits, job listings)
2. Browser history (OPM and USAJobs visits)
3. Bookmark organization
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_federal_pay_research(traj, env_info, task_info):
    # 1. Retrieve result file from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract metadata and reference values
    metadata = task_info.get('metadata', {})
    ref_base = metadata.get('reference_values_2024', {}).get('base', {})
    ref_locality = metadata.get('reference_values_2024', {}).get('locality_step1', {})
    tolerance = metadata.get('tolerance_percent', 10) / 100.0

    score = 0
    feedback = []

    # --- CRITERION 1: JSON Report Structure & Freshness (20 pts) ---
    if result.get('report_exists') and result.get('report_fresh'):
        if result.get('report_valid_json'):
            score += 20
            feedback.append("JSON report created, fresh, and valid (+20)")
        else:
            score += 10
            feedback.append("JSON report exists but has invalid syntax (+10)")
    else:
        feedback.append("JSON report not found or not created during task (0/20)")
        # Gate check: if no report and no browsing, fail immediately
        if result.get('opm_visits', 0) == 0:
            return {"passed": False, "score": 0, "feedback": "No report created and no OPM.gov visits detected."}

    data = result.get('report_data', {})

    # --- CRITERION 2: Base Pay Data Accuracy (20 pts) ---
    base_pay_score = 0
    base_data = data.get('base_pay_2024', {})
    
    # Check 3 grades * 2 steps = 6 checks
    checks_passed = 0
    total_checks = 6
    
    for grade in ['GS-7', 'GS-9', 'GS-12']:
        grade_ref = ref_base.get(grade, {})
        grade_user = base_data.get(grade, {})
        
        for step in ['step1', 'step10']:
            ref_val = grade_ref.get(step, 0)
            # Handle string inputs like "$41,966"
            try:
                user_val_raw = grade_user.get(step, 0)
                if isinstance(user_val_raw, str):
                    user_val = float(user_val_raw.replace('$', '').replace(',', '').strip())
                else:
                    user_val = float(user_val_raw)
            except (ValueError, TypeError):
                user_val = 0
            
            if ref_val > 0 and abs(user_val - ref_val) <= (ref_val * tolerance):
                checks_passed += 1
            elif ref_val > 0:
                pass # Silent fail for specific field to avoid log spam, simplified feedback below

    if checks_passed == 6:
        base_pay_score = 20
        feedback.append("Base pay data fully accurate (+20)")
    elif checks_passed >= 3:
        base_pay_score = 10
        feedback.append(f"Base pay data partially accurate ({checks_passed}/6) (+10)")
    else:
        feedback.append("Base pay data missing or inaccurate (0/20)")
    score += base_pay_score

    # --- CRITERION 3: Locality Pay Data Accuracy (20 pts) ---
    loc_score = 0
    loc_data = data.get('locality_pay_2024_step1', {})
    loc_checks_passed = 0
    loc_total_checks = 9 # 3 areas * 3 grades
    
    for area in ['DCB', 'NY', 'HOU']:
        area_ref = ref_locality.get(area, {})
        area_user = loc_data.get(area, {})
        
        for grade in ['GS-7', 'GS-9', 'GS-12']:
            ref_val = area_ref.get(grade, 0)
            try:
                user_val_raw = area_user.get(grade, 0)
                if isinstance(user_val_raw, str):
                    user_val = float(user_val_raw.replace('$', '').replace(',', '').strip())
                else:
                    user_val = float(user_val_raw)
            except (ValueError, TypeError):
                user_val = 0
            
            if ref_val > 0 and abs(user_val - ref_val) <= (ref_val * tolerance):
                loc_checks_passed += 1

    if loc_checks_passed >= 8:
        loc_score = 20
        feedback.append("Locality pay data accurate (+20)")
    elif loc_checks_passed >= 4:
        loc_score = 10
        feedback.append(f"Locality pay data partially accurate ({loc_checks_passed}/9) (+10)")
    else:
        feedback.append("Locality pay data mostly missing or inaccurate (0/20)")
    score += loc_score

    # --- CRITERION 4: Benefits & Sample Positions (15 pts) ---
    benefits = data.get('benefits_summary', {})
    positions = data.get('sample_positions', [])
    
    misc_score = 0
    # Check Benefits
    if benefits.get('fehb_plan_choices') and benefits.get('fers_basic_formula') and benefits.get('tsp_match_percent'):
        misc_score += 10
        feedback.append("Benefits summary complete (+10)")
    elif len(benefits) > 0:
        misc_score += 5
        feedback.append("Benefits summary partial (+5)")
        
    # Check Positions
    if isinstance(positions, list) and len(positions) >= 2:
        misc_score += 5
        feedback.append("Sample positions listed (+5)")
        
    score += misc_score

    # --- CRITERION 5: Bookmarks & History (25 pts) ---
    nav_score = 0
    
    # History
    opm_visits = result.get('opm_visits', 0)
    usajobs_visits = result.get('usajobs_visits', 0)
    
    if opm_visits > 0:
        nav_score += 5
    if usajobs_visits > 0:
        nav_score += 5
    if opm_visits > 0 or usajobs_visits > 0:
        feedback.append(f"History validated (OPM: {opm_visits}, USAJobs: {usajobs_visits})")

    # Bookmarks
    if result.get('folder_exists'):
        nav_score += 5
        count = result.get('bookmark_count', 0)
        correct_urls = result.get('correct_urls_count', 0)
        
        if count >= 5:
            nav_score += 5
            feedback.append(f"Bookmark count met ({count}/5) (+5)")
        else:
            feedback.append(f"Bookmark count low ({count}/5)")
            
        if correct_urls >= 1:
            nav_score += 5
            feedback.append("Bookmarks contain correct domains (+5)")
    else:
        feedback.append("Required bookmark folder not found (0/15)")
        
    score += nav_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback)
    }