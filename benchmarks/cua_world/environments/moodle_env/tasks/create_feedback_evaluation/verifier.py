#!/usr/bin/env python3
"""Verifier for Create Feedback Evaluation task in Moodle."""

import json
import tempfile
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_feedback_evaluation(traj, env_info, task_info):
    """
    Verify creation of Feedback activity with correct settings and questions.
    
    Scoring Criteria (100 points total):
    1. Activity exists in HIST201 (15 pts)
    2. Activity created AFTER task start (Anti-gaming) (Pass/Fail check mostly, helps score)
    3. Name matches "End of Semester Course Evaluation" (10 pts)
    4. Anonymous set to Yes (10 pts)
    5. Multiple submissions set to No (5 pts)
    6. Question Count >= 5 (15 pts)
    7. Question Types Present:
       - Multichoice (10 pts)
       - Numeric (10 pts)
       - Short Text (Textfield) (5 pts)
       - Long Text (Textarea) (5 pts)
    8. Question Content (Labels match expected topics) (15 pts)
    
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_feedback_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. Activity Existence (15 pts)
        feedback_found = result.get('feedback_found', False)
        if feedback_found:
            score += 15
            feedback_parts.append("Feedback activity found")
        else:
            feedback_parts.append("Feedback activity NOT found")
            return {"passed": False, "score": 0, "feedback": "Activity not found"}

        # 2. Anti-gaming / Timestamp check
        task_start = int(result.get('task_start_time', 0))
        timemodified = int(result.get('timemodified', 0))
        # Allow a small buffer if needed, but timemodified should be > task_start
        if timemodified > task_start:
            feedback_parts.append("Activity created/modified during task")
        else:
            feedback_parts.append("Warning: Activity modification time predates task start")

        # 3. Name Match (10 pts)
        name = result.get('feedback_name', '').lower()
        if 'end of semester' in name and 'evaluation' in name:
            score += 10
            feedback_parts.append("Name correct")
        else:
            feedback_parts.append(f"Name mismatch: '{result.get('feedback_name')}'")

        # 4. Anonymous (10 pts)
        # Moodle mdl_feedback.anonymous: 1 = Anonymous, 2 = Named
        anon_val = int(result.get('anonymous', 0))
        if anon_val == 1:
            score += 10
            feedback_parts.append("Anonymous enabled")
        else:
            feedback_parts.append(f"Anonymous incorrect (Value: {anon_val}, expected 1)")

        # 5. Multiple Submissions (5 pts)
        # Moodle mdl_feedback.multiple_submit: 0 = No, 1 = Yes
        multi_sub = int(result.get('multiple_submit', 1))
        if multi_sub == 0:
            score += 5
            feedback_parts.append("Multiple submissions disabled")
        else:
            feedback_parts.append("Multiple submissions enabled (expected disabled)")

        # 6. Question Count (15 pts)
        items = result.get('items', [])
        # Filter out 'label' or 'pagebreak' types if any, usually we want actual questions
        questions = [i for i in items if i.get('type') not in ['label', 'pagebreak', 'captcha']]
        q_count = len(questions)
        
        if q_count >= 5:
            score += 15
            feedback_parts.append(f"Question count met ({q_count})")
        else:
            feedback_parts.append(f"Insufficient questions ({q_count}/5)")
            score += int(q_count * 3) # Partial credit 3 pts per question

        # 7. Question Types (30 pts total)
        types_found = set(q.get('type') for q in questions)
        
        if 'multichoice' in types_found or 'multichoicerated' in types_found:
            score += 10
            feedback_parts.append("Multichoice present")
        else:
            feedback_parts.append("Missing Multichoice")

        if 'numeric' in types_found:
            score += 10
            feedback_parts.append("Numeric present")
        else:
            feedback_parts.append("Missing Numeric")

        if 'textfield' in types_found:
            score += 5
            feedback_parts.append("Short text present")
        else:
            feedback_parts.append("Missing Short text")

        if 'textarea' in types_found:
            score += 5
            feedback_parts.append("Long text present")
        else:
            feedback_parts.append("Missing Long text")

        # 8. Content Check (15 pts)
        # Check for keywords in question names/labels
        content_score = 0
        keywords = {
            'quality': 3,
            'recommend': 3,
            'valuable': 3,
            'improvement': 3,
            'instructor': 3
        }
        
        all_text = " ".join([q.get('name', '').lower() for q in questions])
        
        matched_keywords = []
        for kw, pts in keywords.items():
            if kw in all_text:
                content_score += pts
                matched_keywords.append(kw)
        
        score += content_score
        if content_score == 15:
            feedback_parts.append("All content topics found")
        elif content_score > 0:
            feedback_parts.append(f"Some topics found: {', '.join(matched_keywords)}")
        else:
            feedback_parts.append("No expected topics found in questions")

        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}