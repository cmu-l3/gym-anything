#!/usr/bin/env python3
"""Verifier for Import Question Bank task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_import_question_bank(traj, env_info, task_info):
    """
    Verify that question category was created and questions imported.

    Scoring (100 points):
    - Category "Pharmacology Module 3" exists (15 pts)
    - Category is in correct BIO101 course context (10 pts)
    - At least 6 questions imported into category (15 pts)
    - All 8 questions imported (15 pts)
    - All questions are multichoice type (10 pts)
    - Question names match expected list (20 pts)
    - Specific correct answers verified (10 pts)
    - Anti-gaming: Created during task (5 pts)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_names = metadata.get('expected_question_names', [])

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/import_question_bank_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Category Existence (15 pts)
        cat_found = result.get('category_found', False)
        if cat_found:
            score += 15
            subscores["category_exists"] = True
            feedback_parts.append("Category 'Pharmacology Module 3' created")
        else:
            subscores["category_exists"] = False
            feedback_parts.append("Category 'Pharmacology Module 3' NOT found")

        # 2. Category Context (10 pts)
        expected_ctx = int(result.get('course_context_id', -1))
        actual_ctx = int(result.get('category_context_id', -2))
        
        if cat_found and expected_ctx > 0 and expected_ctx == actual_ctx:
            score += 10
            subscores["correct_context"] = True
            feedback_parts.append("Category in correct BIO101 context")
        elif cat_found:
            subscores["correct_context"] = False
            feedback_parts.append("Category created in WRONG context (e.g., System or wrong course)")

        # 3. Question Count (30 pts split)
        q_count = int(result.get('question_count', 0))
        if q_count >= 8:
            score += 30 # 15 + 15
            subscores["question_count"] = "Full (8/8)"
            feedback_parts.append("All 8 questions imported")
        elif q_count >= 6:
            score += 15
            subscores["question_count"] = f"Partial ({q_count}/8)"
            feedback_parts.append(f"Most questions imported ({q_count}/8)")
        elif q_count > 0:
            score += 5
            subscores["question_count"] = f"Low ({q_count}/8)"
            feedback_parts.append(f"Some questions imported ({q_count}/8)")
        else:
            subscores["question_count"] = "None"
            feedback_parts.append("No questions found in category")

        # 4. Question Types (10 pts)
        questions = result.get('questions', [])
        if questions and len(questions) > 0:
            all_multichoice = all(q.get('qtype') == 'multichoice' for q in questions)
            if all_multichoice:
                score += 10
                subscores["qtype"] = True
                feedback_parts.append("All questions are Multiple Choice")
            else:
                subscores["qtype"] = False
                feedback_parts.append("Some questions have wrong type (not multichoice)")
        else:
            subscores["qtype"] = False

        # 5. Question Names (20 pts)
        found_names = [q.get('name', '') for q in questions]
        matched_names = 0
        for expected in expected_names:
            # Case-insensitive partial match
            if any(expected.lower() in found.lower() for found in found_names):
                matched_names += 1
        
        if len(expected_names) > 0:
            name_score = int((matched_names / len(expected_names)) * 20)
            score += name_score
            subscores["name_match"] = f"{matched_names}/{len(expected_names)}"
            if matched_names == len(expected_names):
                feedback_parts.append("All question names verified")
            elif matched_names > 0:
                feedback_parts.append(f"{matched_names} question names verified")

        # 6. Content Spot Check (10 pts)
        if result.get('warfarin_check', False):
            score += 5
            feedback_parts.append("Content Verified: Warfarin")
        if result.get('heparin_check', False):
            score += 5
            feedback_parts.append("Content Verified: Heparin")

        # 7. Anti-gaming (5 pts)
        # Check if category creation time is after task start
        task_start = int(result.get('task_start_time', 0))
        cat_created = int(result.get('category_timecreated', 0))
        
        if cat_found and cat_created >= task_start:
            score += 5
            subscores["newly_created"] = True
        elif cat_found:
            feedback_parts.append("Warning: Category creation time predates task start")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}