#!/usr/bin/env python3
"""Verifier for Create Workshop Peer Assessment task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_workshop_peer_assessment(traj, env_info, task_info):
    """
    Verify that the workshop activity was created with correct settings and criteria.
    
    Scoring (100 points):
    - Workshop exists in BIO101 and newly created: 15 pts
    - Name matches 'Lab Report Peer Review': 15 pts
    - Grading strategy is 'accumulative': 15 pts
    - Grade for submission is 80: 10 pts
    - Grade for assessment is 20: 10 pts
    - At least 3 assessment criteria defined: 20 pts
    - Workshop switched to Submission phase (20): 15 pts
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_grading_strategy = metadata.get('grading_strategy', 'accumulative')
    expected_grade_submission = int(metadata.get('grade_submission', 80))
    expected_grade_assessment = int(metadata.get('grade_assessment', 20))
    expected_phase = int(metadata.get('expected_phase', 20))

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_workshop_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Workshop Exists & Location (15 pts)
        workshop_found = result.get('workshop_found', False)
        course_id = str(result.get('course_id', ''))
        workshop_course_id = str(result.get('workshop_course_id', ''))
        newly_created = result.get('newly_created', False)
        
        # Critical check: wrong course
        if workshop_found and workshop_course_id != course_id:
             return {
                "passed": False,
                "score": 0,
                "feedback": f"Workshop created in wrong course (ID {workshop_course_id}, expected {course_id})"
            }

        if workshop_found and newly_created:
            score += 15
            subscores["exists"] = True
            feedback_parts.append("Workshop created in BIO101")
        elif workshop_found:
            # Partial credit if found but timestamp check fails (maybe clock skew or slow start)
            score += 5
            subscores["exists"] = False
            feedback_parts.append("Workshop found (pre-existing?)")
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Workshop not found in BIO101",
                "subscores": subscores
            }

        # 2. Name Check (15 pts)
        name = result.get('workshop_name', '').lower()
        if 'lab report' in name and 'peer review' in name:
            score += 15
            subscores["name"] = True
            feedback_parts.append("Name correct")
        else:
            subscores["name"] = False
            feedback_parts.append(f"Name mismatch: '{result.get('workshop_name')}'")

        # 3. Strategy Check (15 pts)
        strategy = result.get('strategy', '')
        if strategy == expected_grading_strategy:
            score += 15
            subscores["strategy"] = True
            feedback_parts.append("Strategy: accumulative")
        else:
            subscores["strategy"] = False
            feedback_parts.append(f"Strategy incorrect: {strategy}")

        # 4. Grade Settings (20 pts total)
        g_sub = int(result.get('grade_submission', 0))
        g_ass = int(result.get('grade_assessment', 0))
        
        if g_sub == expected_grade_submission:
            score += 10
            feedback_parts.append("Submission grade correct (80)")
        else:
            feedback_parts.append(f"Submission grade: {g_sub} (exp 80)")
            
        if g_ass == expected_grade_assessment:
            score += 10
            feedback_parts.append("Assessment grade correct (20)")
        else:
            feedback_parts.append(f"Assessment grade: {g_ass} (exp 20)")

        # 5. Criteria Check (20 pts)
        # Only valid if strategy was accumulative
        criteria_count = int(result.get('criteria_count', 0))
        descriptions = result.get('criteria_descriptions', '').lower()
        
        if criteria_count >= 3:
            # Check content for keywords
            keywords = ["accuracy", "writing", "data", "presentation"]
            found_keywords = sum(1 for k in keywords if k in descriptions)
            
            if found_keywords >= 2:
                score += 20
                subscores["criteria"] = True
                feedback_parts.append(f"Criteria defined ({criteria_count}) with valid content")
            else:
                score += 10
                subscores["criteria"] = False
                feedback_parts.append(f"Criteria count ok ({criteria_count}) but content generic/missing")
        elif criteria_count > 0:
            score += int(criteria_count * 5) # 5 pts per criterion
            subscores["criteria"] = False
            feedback_parts.append(f"Only {criteria_count} criteria defined")
        else:
            subscores["criteria"] = False
            feedback_parts.append("No assessment criteria defined")

        # 6. Phase Check (15 pts)
        # Phase 10 = Setup, 20 = Submission, 30 = Assessment
        phase = int(result.get('phase', 0))
        if phase == expected_phase:
            score += 15
            subscores["phase"] = True
            feedback_parts.append("Phase: Submission")
        elif phase > 20:
             # Also accept if they went further to Assessment phase
            score += 15
            subscores["phase"] = True
            feedback_parts.append(f"Phase advanced ({phase})")
        else:
            subscores["phase"] = False
            feedback_parts.append(f"Phase incorrect: {phase} (expected {expected_phase})")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON result"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}