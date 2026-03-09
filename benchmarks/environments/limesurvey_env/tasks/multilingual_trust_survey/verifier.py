#!/usr/bin/env python3
"""
Verifier for multilingual_trust_survey task.

SCORING CRITERIA:
1. Survey exists with correct English title (Gate)
2. Spanish language enabled (15 pts)
3. Spanish title correct (10 pts)
4. Question Groups: >=2 created (10 pts), Spanish names present (15 pts)
5. Questions: >=5 created (10 pts), Spanish text present (20 pts)
6. Array question has sub-questions (10 pts)
7. Survey Activated (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multilingual_trust_survey(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback_parts = []
    
    # 1. Gate: Survey Found
    if not result.get('survey_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No survey found. Did you create it?"
        }
    
    # Check English Title (Gate)
    title_en = result.get('title_en', '')
    if "Social Trust" not in title_en:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Survey found but title incorrect: '{title_en}' (Expected 'Social Trust' in title)"
        }
    
    # 2. Spanish Language Enabled (15 pts)
    langs = result.get('additional_languages', '')
    if 'es' in langs.split():
        score += 15
        feedback_parts.append("Spanish language enabled")
    else:
        feedback_parts.append("Spanish language NOT enabled")

    # 3. Spanish Title (10 pts)
    title_es = result.get('title_es', '')
    if "Confianza" in title_es or "Social" in title_es:
        score += 10
        feedback_parts.append("Spanish title present")
    else:
        feedback_parts.append("Spanish title missing or incorrect")

    # 4. Question Groups (25 pts total)
    group_count = result.get('group_count', 0)
    group_es_count = result.get('group_es_count', 0)
    
    if group_count >= 2:
        score += 10
        feedback_parts.append(f"Question groups created ({group_count})")
    else:
        feedback_parts.append(f"Insufficient groups ({group_count}/2)")
        
    if group_es_count >= 2:
        score += 15
        feedback_parts.append("Groups translated to Spanish")
    elif group_es_count > 0:
        score += 7
        feedback_parts.append("Some groups translated")
    else:
        feedback_parts.append("Groups NOT translated")

    # 5. Questions (30 pts total)
    q_count = result.get('question_count', 0)
    q_es_count = result.get('question_es_count', 0)
    
    if q_count >= 5:
        score += 10
        feedback_parts.append(f"Questions created ({q_count})")
    else:
        feedback_parts.append(f"Insufficient questions ({q_count}/5)")
        
    if q_es_count >= 5:
        score += 20
        feedback_parts.append("Questions translated to Spanish")
    elif q_es_count > 0:
        # Partial credit
        partial = int(20 * (q_es_count / 5))
        score += partial
        feedback_parts.append(f"Some questions translated ({q_es_count}/5)")
    else:
        feedback_parts.append("Questions NOT translated")

    # 6. Array Subquestions (10 pts)
    # The task requires one array question with at least 4 subquestions (Institutions)
    array_subq = result.get('array_subq_count', 0)
    if array_subq >= 4:
        score += 10
        feedback_parts.append("Array question structure correct")
    else:
        feedback_parts.append("Array question sub-questions missing")

    # 7. Activation (10 pts)
    active = result.get('active', 'N')
    if active == 'Y':
        score += 10
        feedback_parts.append("Survey is Active")
    else:
        feedback_parts.append("Survey NOT active")
        
    # Check for meaningful content (Anti-gaming)
    # If they just created 5 empty questions with no Spanish text, q_es_count handles it.
    # We also check answer options if possible, though strict grading there might be fragile.
    answer_es = result.get('answer_option_es_count', 0)
    if answer_es > 5:
        feedback_parts.append("Answer options translated")
    else:
        feedback_parts.append("Warning: Few answer options translated")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }