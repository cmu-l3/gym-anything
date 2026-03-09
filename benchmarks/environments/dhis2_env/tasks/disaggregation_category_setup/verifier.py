#!/usr/bin/env python3
"""
Verifier for disaggregation_category_setup task.

Scoring (100 points total):
1. Category Options Created (30 pts)
   - At least 1 created (15 pts) [MANDATORY]
   - All 3 correct names created (15 pts)
2. Category Created (40 pts)
   - Category exists with correct name (20 pts)
   - Category contains >= 2 correct options (10 pts)
   - Category contains all 3 correct options (10 pts)
3. Category Combination Created (30 pts)
   - Combo exists with correct name (20 pts)
   - Combo references the correct category (10 pts)

Anti-gaming:
- Checks 'created' timestamp against task start time.
- Verifies hierarchical relationships, not just flat existence.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def parse_dhis2_date(date_str):
    """Parse DHIS2 ISO date string to datetime object."""
    # Handle '2023-10-25T12:00:00.000' or with 'Z'
    try:
        clean_str = date_str.replace('Z', '')
        # Truncate microseconds if they are too long or variable
        if '.' in clean_str:
            main, micro = clean_str.split('.')
            clean_str = f"{main}.{micro[:6]}"
        return datetime.fromisoformat(clean_str)
    except Exception:
        return None

def verify_disaggregation_setup(traj, env_info, task_info):
    """Verify the creation of DHIS2 metadata for pregnancy trimester disaggregation."""
    
    # 1. Retrieve Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/disaggregation_setup_result.json", temp_path)
        
        with open(temp_path, 'r') as f:
            result = json.load(f)
        
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"API Query Error: {result['error']}"}

    # 2. Parse Data & Timestamps
    task_start_str = result.get('task_start')
    task_start = parse_dhis2_date(task_start_str) if task_start_str else datetime.min
    
    options = result.get('options', [])
    categories = result.get('categories', [])
    combos = result.get('combos', [])

    score = 0
    feedback = []

    # 3. Verify Category Options (30 pts)
    # Expected: "1st Trimester", "2nd Trimester", "3rd Trimester"
    expected_opts = ["1st trimester", "2nd trimester", "3rd trimester"]
    found_opts = []
    
    for opt in options:
        # Check timestamp
        created_at = parse_dhis2_date(opt.get('created', ''))
        if created_at and created_at < task_start:
            continue # Skip old objects
            
        name_lower = opt.get('name', '').lower()
        # Fuzzy matching
        for exp in expected_opts:
            if exp in name_lower:
                found_opts.append(opt)
                break
    
    # Remove duplicates based on ID
    unique_found_opts = {o['id']: o for o in found_opts}.values()
    found_count = len(unique_found_opts)

    # Score Options
    if found_count >= 1:
        score += 15
        feedback.append(f"Created {found_count} Category Option(s) (+15)")
    else:
        return {"passed": False, "score": 0, "feedback": "No new 'Trimester' Category Options created."}

    if found_count >= 3:
        score += 15
        feedback.append("All 3 Category Options created (+15)")
    else:
        feedback.append(f"Missing some options (found {found_count}/3)")

    # 4. Verify Category (40 pts)
    # Expected: "Pregnancy Trimester", contains the options
    target_cat = None
    for cat in categories:
        created_at = parse_dhis2_date(cat.get('created', ''))
        if created_at and created_at < task_start:
            continue
            
        if "pregnancy" in cat.get('name', '').lower() and "trimester" in cat.get('name', '').lower():
            target_cat = cat
            break
            
    if target_cat:
        score += 20
        feedback.append(f"Category '{target_cat.get('name')}' created (+20)")
        
        # Check Dimension Type
        if target_cat.get('dataDimensionType') == 'DISAGGREGATION':
            feedback.append("Correct dimension type (implicit)")
        else:
            feedback.append(f"Warning: Dimension type is {target_cat.get('dataDimensionType')}, expected DISAGGREGATION")

        # Check Linked Options
        linked_opts = target_cat.get('categoryOptions', [])
        linked_count = 0
        
        # Verify the linked options are the correct ones (Trimester ones)
        for lo in linked_opts:
            lo_name = lo.get('name', '').lower()
            if any(e in lo_name for e in expected_opts):
                linked_count += 1
        
        if linked_count >= 2:
            score += 10
            feedback.append(f"Category contains {linked_count} trimester options (+10)")
        else:
            feedback.append(f"Category only contains {linked_count} trimester options (need >= 2)")
            
        if linked_count >= 3:
            score += 10
            feedback.append("Category contains all 3 required options (+10)")
    else:
        feedback.append("No new Category named 'Pregnancy Trimester' found")

    # 5. Verify Category Combination (30 pts)
    # Expected: "Pregnancy Trimester Disaggregation", contains the category
    target_combo = None
    for combo in combos:
        created_at = parse_dhis2_date(combo.get('created', ''))
        if created_at and created_at < task_start:
            continue
            
        # Flexible name matching
        name = combo.get('name', '').lower()
        if "pregnancy" in name and "disaggregation" in name:
            target_combo = combo
            break
    
    if target_combo:
        score += 20
        feedback.append(f"Category Combination '{target_combo.get('name')}' created (+20)")
        
        # Check Linked Category
        linked_cats = target_combo.get('categories', [])
        has_correct_link = False
        
        if target_cat:
            target_id = target_cat.get('id')
            for lc in linked_cats:
                if lc.get('id') == target_id:
                    has_correct_link = True
                    break
        
        if has_correct_link:
            score += 10
            feedback.append("Combination correctly linked to Category (+10)")
        else:
            feedback.append("Combination NOT linked to the created Category")
    else:
        feedback.append("No new Category Combination found")

    # Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }