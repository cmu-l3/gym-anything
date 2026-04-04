#!/usr/bin/env python3
"""
Verifier for Event Cost Estimator Task (LimeSurvey ExpressionScript).

Scoring Logic:
1. Survey exists and is active (10 pts)
2. 'guests' question exists and is Numerical (N) (15 pts)
3. 'package' question exists and is List Radio (L) (15 pts)
4. 'package' answer codes are exactly 25, 55, 120 (Critical for math) (30 pts)
5. 'total_cost' question exists, is Equation (*), and formula contains multiplication (30 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_event_cost_estimator(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve result file
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    # 1. Survey Check (10 pts)
    if result.get("survey_found", False):
        if result.get("active", "N") == "Y":
            score += 10
            feedback_parts.append("Survey active [10/10]")
        else:
            score += 5
            feedback_parts.append("Survey created but NOT active [5/10]")
    else:
        return {"passed": False, "score": 0, "feedback": "Survey 'Event Quote Calculator 2025' not found"}

    questions = result.get("questions", {})
    
    # 2. Guests Question (15 pts)
    q_guests = questions.get("guests", {})
    if q_guests.get("exists", False):
        q_type = q_guests.get("type", "")
        if q_type == "N": # Numerical
            score += 15
            feedback_parts.append("'guests' question correct (Numerical) [15/15]")
        else:
            score += 5
            feedback_parts.append(f"'guests' question exists but wrong type '{q_type}' (expected N) [5/15]")
    else:
        feedback_parts.append("'guests' question missing [0/15]")

    # 3. Package Question (15 pts)
    q_package = questions.get("package", {})
    if q_package.get("exists", False):
        q_type = q_package.get("type", "")
        if q_type == "L": # List (Radio)
            score += 15
            feedback_parts.append("'package' question correct (List Radio) [15/15]")
        else:
            score += 5
            feedback_parts.append(f"'package' question exists but wrong type '{q_type}' (expected L) [5/15]")
    else:
        feedback_parts.append("'package' question missing [0/15]")

    # 4. Package Answer Codes (30 pts) - CRITICAL
    # Expected: "25", "55", "120" (order doesn't strict matter if regex match, but logic requires these numbers)
    # The export script groups them comma separated
    answer_codes_str = q_package.get("answer_codes", "")
    required_codes = ["25", "55", "120"]
    missing_codes = [c for c in required_codes if c not in answer_codes_str.split(',')]
    
    if not missing_codes and answer_codes_str:
        score += 30
        feedback_parts.append("Answer codes correct (Prices) [30/30]")
    elif answer_codes_str:
        # Partial credit if they tried but got it wrong (e.g. A1, A2)
        feedback_parts.append(f"Answer codes incorrect: Found '{answer_codes_str}', expected 25, 55, 120. Math will fail. [0/30]")
    else:
        feedback_parts.append("No answer options found for 'package' [0/30]")

    # 5. Total Cost Equation (30 pts)
    q_cost = questions.get("total_cost", {})
    if q_cost.get("exists", False):
        q_type = q_cost.get("type", "")
        formula = q_cost.get("formula", "").lower()
        
        if q_type == "*": # Equation type
            # Check logic: needs 'guests', 'package', and multiplication
            if "guests" in formula and "package" in formula and "*" in formula:
                score += 30
                feedback_parts.append("Equation logic correct [30/30]")
            else:
                score += 15
                feedback_parts.append(f"Equation question exists but formula looks wrong: '{formula}' [15/30]")
        else:
            feedback_parts.append(f"'total_cost' is type '{q_type}', expected Equation (*) [0/30]")
    else:
        feedback_parts.append("'total_cost' question missing [0/30]")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }