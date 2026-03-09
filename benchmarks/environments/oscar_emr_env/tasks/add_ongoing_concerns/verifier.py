#!/usr/bin/env python3
"""
Verifier for add_ongoing_concerns@1
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_ongoing_concerns(traj, env_info, task_info):
    """
    Verifies that the agent added 3 specific ongoing concerns to Maria Santos's record.
    
    Criteria:
    1. 'Diabetes' type issue exists and is active (25 pts)
    2. 'Hypertension' type issue exists and is active (25 pts)
    3. 'Depression' type issue exists and is active (25 pts)
    4. Anti-gaming: Issues were actually added (count increased) (15 pts)
    5. Issues linked to correct patient (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result data
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

    # 2. Extract Data
    issues = result.get('issues', [])
    initial_count = result.get('initial_issue_count', 0)
    current_count = len(issues)
    
    logger.info(f"Found {current_count} issues (Initial: {initial_count})")
    
    score = 0
    feedback_parts = []
    
    # Define required conditions and keywords
    conditions = {
        'Diabetes': {'keywords': ['diabetes', 'dm', 'type 2', 't2dm'], 'found': False, 'active': False},
        'Hypertension': {'keywords': ['hypertension', 'htn', 'blood pressure', 'hbp'], 'found': False, 'active': False},
        'Depression': {'keywords': ['depress', 'mdd', 'mood'], 'found': False, 'active': False}
    }
    
    # 3. Check for conditions
    for issue in issues:
        desc = issue.get('description', '').lower()
        # OSCAR 'resolved' field: '1' is resolved (inactive), '0' or null is active
        # Sometimes it might be the string 'active' depending on the view, but DB usually uses 1/0
        is_resolved = str(issue.get('resolved', '0')).strip() in ['1', 'true', 'yes']
        is_active = not is_resolved
        
        for name, cond in conditions.items():
            if cond['found']: continue # Already found this one
            
            for kw in cond['keywords']:
                if kw in desc:
                    cond['found'] = True
                    cond['active'] = is_active
                    logger.info(f"Matched '{name}' with issue: '{desc}' (Active: {is_active})")
                    break
    
    # 4. Scoring
    
    # Condition Scores (25 pts each)
    for name, cond in conditions.items():
        if cond['found']:
            if cond['active']:
                score += 25
                feedback_parts.append(f"✅ Added active {name}")
            else:
                score += 10 # Partial credit for resolved/inactive issue
                feedback_parts.append(f"⚠️ Added {name} but marked as resolved/inactive")
        else:
            feedback_parts.append(f"❌ Missing {name}")

    # Patient Linkage Score (10 pts)
    # If we found any conditions, they came from the query filtered by patient_id, so linkage is implied correct.
    conditions_found_count = sum(1 for c in conditions.values() if c['found'])
    if conditions_found_count == 3:
        score += 10
        feedback_parts.append("✅ All issues linked to correct patient")
    elif conditions_found_count > 0:
        score += 5
        feedback_parts.append("✅ Some issues linked to correct patient")
    else:
        feedback_parts.append("❌ No relevant issues found on patient record")

    # Anti-gaming / New Data Score (15 pts)
    # Check if count increased
    if current_count > initial_count:
        if current_count >= initial_count + 3:
            score += 15
            feedback_parts.append("✅ New issues verified (count increased)")
        else:
            score += 10
            feedback_parts.append("⚠️ Issue count increased but less than expected")
    elif conditions_found_count > 0:
        # If we found conditions but count didn't increase, maybe we failed to clear initially?
        # Or agent edited existing ones. We give some points if content matches.
        score += 5
        feedback_parts.append("⚠️ Content correct but no net increase in records")
    else:
        feedback_parts.append("❌ No new data created")

    # 5. Final Result
    passed = (score >= 85) # Needs basically everything correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }