#!/usr/bin/env python3
"""
Verifier for Implement ACF Employee Directory task.

Programmatic verification evaluates JSON exported from database queries:
1. Plugin Active (10 pts)
2. Posts Created (10 pts - 5 per post)
3. Category Assignment (10 pts - 5 per post)
4. Job Title Meta (20 pts - 10 per post)
5. Department Meta (10 pts - 5 per post)
6. Extension Meta (10 pts - 5 per post)
7. ACF Integration Validated (30 pts - 15 per post) - Ensures hidden `_fieldname` -> `field_xxx` references exist

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_acf_implementation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_emp1 = metadata.get('employees', {}).get('emp1', {})
    expected_emp2 = metadata.get('employees', {}).get('emp2', {})

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/acf_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load or parse JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    acf_active = result.get('acf_active', False)
    emp1 = result.get('emp1', {})
    emp2 = result.get('emp2', {})

    # 1. Plugin Active (10 points)
    if acf_active:
        score += 10
        feedback.append("ACF Plugin is active (+10)")
    else:
        feedback.append("ACF Plugin is NOT active (0/10)")

    def eval_employee(emp_data, expected_data, emp_label):
        pts = 0
        local_fb = []
        
        # Exists
        if emp_data.get('exists', False):
            pts += 5
            local_fb.append(f"{emp_label} post created")
        else:
            local_fb.append(f"{emp_label} post MISSING")
            return pts, local_fb # Cannot check further if missing
            
        # Category
        if emp_data.get('in_category', False):
            pts += 5
            local_fb.append(f"{emp_label} in Team category")
        else:
            local_fb.append(f"{emp_label} NOT in Team category")
            
        # Job Title (10 pts)
        actual_job = emp_data.get('job_title', '').strip()
        if actual_job.lower() == expected_data.get('job_title', '').lower():
            pts += 10
            local_fb.append(f"{emp_label} job_title correct")
        else:
            local_fb.append(f"{emp_label} job_title incorrect ('{actual_job}')")
            
        # Department (5 pts)
        actual_dept = emp_data.get('department', '').strip()
        if actual_dept.lower() == expected_data.get('department', '').lower():
            pts += 5
            local_fb.append(f"{emp_label} department correct")
        else:
            local_fb.append(f"{emp_label} department incorrect ('{actual_dept}')")
            
        # Office Extension (5 pts)
        actual_ext = emp_data.get('office_extension', '').strip()
        if actual_ext.lower() == expected_data.get('office_extension', '').lower():
            pts += 5
            local_fb.append(f"{emp_label} office_extension correct")
        else:
            local_fb.append(f"{emp_label} office_extension incorrect ('{actual_ext}')")
            
        # ACF Integration (15 pts) - check if ANY hidden key starts with 'field_' (which is ACF's signature)
        hidden_keys = [
            emp_data.get('acf_hidden_job', ''),
            emp_data.get('acf_hidden_dept', ''),
            emp_data.get('acf_hidden_ext', '')
        ]
        
        if any(k.startswith('field_') for k in hidden_keys):
            pts += 15
            local_fb.append(f"{emp_label} ACF integration verified")
        else:
            local_fb.append(f"{emp_label} ACF integration FAILED (no hidden field_ keys, likely used native WP fields instead of ACF)")
            
        return pts, local_fb

    # Evaluate Emp 1
    p1_score, p1_fb = eval_employee(emp1, expected_emp1, "Emp1 (Emily)")
    score += p1_score
    feedback.extend(p1_fb)

    # Evaluate Emp 2
    p2_score, p2_fb = eval_employee(emp2, expected_emp2, "Emp2 (Marcus)")
    score += p2_score
    feedback.extend(p2_fb)

    # Determine passing
    # Threshold 70, requires Plugin Active, both posts created, and some ACF integration
    passed = False
    if score >= 70 and acf_active and emp1.get('exists') and emp2.get('exists'):
        # Enforce that ACF was actually used on at least one post
        if any(k.startswith('field_') for k in [emp1.get('acf_hidden_job',''), emp2.get('acf_hidden_job','')]):
            passed = True

    final_feedback = f"Score: {score}/100. " + " | ".join(feedback)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }