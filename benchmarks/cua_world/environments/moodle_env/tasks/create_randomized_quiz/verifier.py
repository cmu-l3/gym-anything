#!/usr/bin/env python3
"""Verifier for Create Randomized Quiz task."""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_randomized_quiz(traj, env_info, task_info):
    """
    Verify the quiz configuration.
    
    Criteria:
    1. Quiz exists in correct course and was newly created (20 pts)
    2. Quiz name matches (10 pts)
    3. Exactly 5 questions/slots added (20 pts)
    4. Questions are configured as RANDOM (30 pts)
    5. Random questions pull from correct category (10 pts)
    6. Grade to pass is 4.00 (5 pts)
    7. Attempts is Unlimited (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/random_quiz_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. Existence & Anti-Gaming (20 pts)
        quiz_found = result.get('quiz_found', False)
        newly_created = result.get('newly_created', False)
        
        if quiz_found and newly_created:
            score += 20
            feedback_parts.append("Quiz created successfully")
        elif quiz_found:
            score += 10
            feedback_parts.append("Quiz found but timestamp indicates pre-existence")
        else:
            return {"passed": False, "score": 0, "feedback": "Quiz 'Weekly Interaction Check' not found in PHARM101"}

        # 2. Name Match (10 pts)
        name = result.get('quiz_name', '')
        if "Weekly Interaction Check" in name:
            score += 10
            feedback_parts.append("Name correct")
        else:
            feedback_parts.append(f"Name incorrect ('{name}')")

        # 3. Slot Count (20 pts)
        slots = int(result.get('slot_count', 0))
        if slots == 5:
            score += 20
            feedback_parts.append("5 questions added")
        else:
            feedback_parts.append(f"Wrong question count: {slots} (expected 5)")

        # 4. Randomness Check (30 pts) - CRITICAL
        # We verify that slots are linked to question sets (random) rather than specific question versions
        random_slots = int(result.get('random_slot_count', 0))
        
        if random_slots == 5:
            score += 30
            feedback_parts.append("All questions are configured as RANDOM")
        elif random_slots > 0:
            score += 15
            feedback_parts.append(f"Only {random_slots}/5 questions are random")
        else:
            feedback_parts.append("Questions are FIXED, not RANDOM (User added specific questions instead of random slots)")

        # 5. Category Source (10 pts)
        if result.get('correct_category_source', False):
            score += 10
            feedback_parts.append("Random source is 'Drug Interactions'")
        else:
            if random_slots > 0:
                feedback_parts.append("Random questions pulling from WRONG category")

        # 6. Grade to pass (5 pts)
        gradepass = float(result.get('gradepass', 0.0))
        if math.isclose(gradepass, 4.0, abs_tol=0.01):
            score += 5
            feedback_parts.append("Grade to pass: 4.00")
        else:
            feedback_parts.append(f"Grade to pass incorrect ({gradepass})")

        # 7. Attempts (5 pts)
        attempts = int(result.get('attempts', -1))
        if attempts == 0: # 0 means unlimited
            score += 5
            feedback_parts.append("Attempts: Unlimited")
        else:
            feedback_parts.append(f"Attempts limited to {attempts}")

        passed = score >= 80 and quiz_found and random_slots == 5
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}