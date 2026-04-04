#!/usr/bin/env python3
"""Verifier for Configure Gradebook Weights task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_gradebook_weights(traj, env_info, task_info):
    """
    Verify gradebook weight configuration in BIO101.

    Scoring (100 points):
    - Criterion 1: Aggregation changed to Weighted mean of grades (20 points) - CRITICAL
    - Criterion 2: Lab Reports category exists (20 points)
    - Criterion 3: Exams category exists (20 points)
    - Criterion 4: Lab Reports weight approximately 40 (20 points)
    - Criterion 5: Exams weight approximately 60 (20 points)

    Pass threshold: 60 points (must have weighted mean + both categories)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_gradebook_weights_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Aggregation set to Weighted mean (20 points)
        # Moodle aggregation codes: 0=Mean, 10=Weighted mean, 11=Simple weighted mean, 13=Natural
        root_agg = int(result.get('root_aggregation', 0))
        initial_agg = int(result.get('initial_aggregation', 13))

        if root_agg == 10:
            score += 20
            subscores["weighted_mean"] = True
            feedback_parts.append("Aggregation: Weighted mean of grades")
        elif root_agg == 11:
            # Simple weighted mean is close - partial credit
            score += 10
            subscores["weighted_mean"] = False
            feedback_parts.append("Aggregation: Simple weighted mean (expected Weighted mean)")
        elif root_agg != initial_agg:
            score += 5
            subscores["weighted_mean"] = False
            feedback_parts.append(f"Aggregation changed to {root_agg} (expected 10=Weighted mean)")
        else:
            subscores["weighted_mean"] = False
            feedback_parts.append(f"Aggregation not changed (still {root_agg})")

        # Criterion 2: Lab Reports category exists (20 points)
        if result.get('lab_reports_found', False):
            score += 20
            subscores["lab_reports_exists"] = True
            feedback_parts.append("Lab Reports category created")
        else:
            subscores["lab_reports_exists"] = False
            feedback_parts.append("Lab Reports category not found")

        # Criterion 3: Exams category exists (20 points)
        if result.get('exams_found', False):
            score += 20
            subscores["exams_exists"] = True
            feedback_parts.append("Exams category created")
        else:
            subscores["exams_exists"] = False
            feedback_parts.append("Exams category not found")

        # Criterion 4: Lab Reports weight ~40 (20 points)
        try:
            lr_weight = float(result.get('lab_reports_weight', 0))
        except (ValueError, TypeError):
            lr_weight = 0.0

        if 35.0 <= lr_weight <= 45.0:
            score += 20
            subscores["lab_reports_weight"] = True
            feedback_parts.append(f"Lab Reports weight: {lr_weight}")
        elif lr_weight > 0:
            score += 5
            subscores["lab_reports_weight"] = False
            feedback_parts.append(f"Lab Reports weight: {lr_weight} (expected ~40)")
        else:
            subscores["lab_reports_weight"] = False
            feedback_parts.append("Lab Reports weight not set")

        # Criterion 5: Exams weight ~60 (20 points)
        try:
            ex_weight = float(result.get('exams_weight', 0))
        except (ValueError, TypeError):
            ex_weight = 0.0

        if 55.0 <= ex_weight <= 65.0:
            score += 20
            subscores["exams_weight"] = True
            feedback_parts.append(f"Exams weight: {ex_weight}")
        elif ex_weight > 0:
            score += 5
            subscores["exams_weight"] = False
            feedback_parts.append(f"Exams weight: {ex_weight} (expected ~60)")
        else:
            subscores["exams_weight"] = False
            feedback_parts.append("Exams weight not set")

        # Pass: need weighted mean + both categories at minimum
        passed = (score >= 60
                  and subscores.get("weighted_mean", False)
                  and subscores.get("lab_reports_exists", False)
                  and subscores.get("exams_exists", False))

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
