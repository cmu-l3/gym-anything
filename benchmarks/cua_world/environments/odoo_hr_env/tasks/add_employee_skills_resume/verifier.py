#!/usr/bin/env python3
"""
Verifier for add_employee_skills_resume task.

Checks:
1. Python Skill (Expert) added for Eli Lambert.
2. Spanish Skill (Intermediate) added for Eli Lambert.
3. Resume Line "Senior Developer at TechCorp" (2019-2023) added.
4. All records created AFTER task start time (Anti-Gaming).
"""

import json
import logging
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_employee_skills_resume(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    # Scoring Configuration
    score = 0
    feedback = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_skills = metadata.get('target_skills', [])
    target_resume = metadata.get('target_resume', {})

    skills_found = result.get('skills_found', [])
    resume_found = result.get('resume_lines_found', [])
    app_running = result.get('app_running', False)

    if not app_running:
        return {"passed": False, "score": 0, "feedback": "Odoo was not accessible during verification."}

    # Verify Skills
    python_passed = False
    spanish_passed = False

    for s in skills_found:
        # Check Python
        if s.get('skill') == 'Python' and s.get('created_after_start'):
            if s.get('level') == 'Expert':
                score += 25
                python_passed = True
                feedback.append("Added Python (Expert).")
            else:
                score += 10
                feedback.append(f"Added Python but wrong level ({s.get('level')}).")
        
        # Check Spanish
        if s.get('skill') == 'Spanish' and s.get('created_after_start'):
            if s.get('level') == 'Intermediate':
                score += 25
                spanish_passed = True
                feedback.append("Added Spanish (Intermediate).")
            else:
                score += 10
                feedback.append(f"Added Spanish but wrong level ({s.get('level')}).")

    if not python_passed:
        feedback.append("Missing or pre-existing Python skill.")
    if not spanish_passed:
        feedback.append("Missing or pre-existing Spanish skill.")

    # Verify Resume
    resume_passed = False
    for r in resume_found:
        if not r.get('created_after_start'):
            continue
        
        # Check Name (loose matching)
        name_match = "Senior Developer" in r.get('name', '') and "TechCorp" in r.get('name', '')
        
        # Check Dates
        start_match = "2019-01-01" in str(r.get('date_start', ''))
        end_match = "2023-12-31" in str(r.get('date_end', ''))
        
        type_match = r.get('type') == 'Experience'

        if name_match:
            if start_match and end_match and type_match:
                score += 50
                resume_passed = True
                feedback.append("Added correct Resume Experience.")
                break
            else:
                # Partial credit
                partial_score = 20
                details = []
                if start_match and end_match:
                    partial_score += 10
                else:
                    details.append(f"Dates wrong ({r.get('date_start')} - {r.get('date_end')})")
                
                if type_match:
                    partial_score += 10
                else:
                    details.append(f"Type wrong ({r.get('type')})")
                
                score += partial_score
                feedback.append(f"Resume entry found with issues: {', '.join(details)}")
                resume_passed = True # Found the entry, just imperfect
                break
    
    if not resume_passed:
        feedback.append("Missing valid Resume entry for Senior Developer at TechCorp.")

    passed = (python_passed and spanish_passed and resume_passed) and score >= 80

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }