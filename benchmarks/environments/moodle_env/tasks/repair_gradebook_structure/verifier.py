#!/usr/bin/env python3
"""Verifier for Repair Gradebook Structure task in Moodle.

Scoring breakdown (100 points total):
  Criterion 1 — Top-level aggregation = Weighted mean (code 10): 20 pts  [CRITICAL]
  Criterion 2 — Problem Sets category exists: 10 pts
               Problem Sets weight = 30 (±6): 10 pts
  Criterion 3 — Lab Reports category exists: 10 pts
               Lab Reports weight = 30 (±6): 10 pts
  Criterion 4 — Exams category exists: 10 pts
               Exams weight = 40 (±6): 10 pts
  Criterion 5 — Midterm Exam weight within Exams ≈ 40 (±8): 5 pts
               Final Exam weight within Exams ≈ 60 (±8): 5 pts

Pass threshold: score >= 60 AND criterion 1 fully satisfied (agg == 10).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _to_float(value, default: float = 0.0) -> float:
    """Safely convert a value to float, returning default on failure."""
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def verify_repair_gradebook_structure(traj, env_info, task_info):
    """
    Verify that the CHEM201 gradebook has been correctly restructured.

    Expected state:
      - Top-level aggregation = 10 (Weighted mean of grades)
      - Sub-category "Problem Sets" with weight ~30
      - Sub-category "Lab Reports" with weight ~30
      - Sub-category "Exams" with weight ~40
      - Within Exams: Midterm Exam weight ~40, Final Exam weight ~60

    Returns a dict with keys: passed (bool), score (int), feedback (str),
    subscores (dict).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available — cannot retrieve result file",
        }

    metadata = task_info.get('metadata', {})
    expected_top_agg = int(metadata.get('expected_top_aggregation', 10))
    expected_categories = metadata.get('categories', {
        'Problem Sets': 30,
        'Lab Reports': 30,
        'Exams': 40,
    })
    expected_subweights = metadata.get('exams_subweights', {
        'Midterm Exam': 40,
        'Final Exam': 60,
    })

    try:
        # Copy result file out of the VM/container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_result.close()
        try:
            copy_from_env("/tmp/repair_gradebook_structure_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_result.name)
            except OSError:
                pass

        logger.info("Result data: %s", json.dumps(result, indent=2))

        score = 0
        feedback_parts = []
        subscores = {}

        # ------------------------------------------------------------------
        # Criterion 1 — Top-level aggregation (20 points, CRITICAL)
        # Moodle aggregation codes:
        #   0  = Mean of grades
        #   10 = Weighted mean of grades  ← correct
        #   11 = Simple weighted mean
        #   13 = Natural weighting
        # ------------------------------------------------------------------
        top_agg = int(result.get('top_aggregation', 0))

        if top_agg == expected_top_agg:  # 10
            score += 20
            subscores['top_aggregation_correct'] = True
            feedback_parts.append(
                f"Top-level aggregation: Weighted mean of grades (code {top_agg}) [20/20]"
            )
        elif top_agg == 11:
            # Simple weighted mean — a common near-miss; give partial credit
            score += 8
            subscores['top_aggregation_correct'] = False
            feedback_parts.append(
                f"Top-level aggregation: Simple weighted mean (code 11), "
                f"expected Weighted mean (code 10) [8/20]"
            )
        elif top_agg != 0:
            # Changed from the broken state (0=Mean), but not the right value
            score += 4
            subscores['top_aggregation_correct'] = False
            feedback_parts.append(
                f"Top-level aggregation changed to code {top_agg}, "
                f"expected code 10 (Weighted mean) [4/20]"
            )
        else:
            subscores['top_aggregation_correct'] = False
            feedback_parts.append(
                f"Top-level aggregation still Mean (code 0) — not changed [0/20]"
            )

        # ------------------------------------------------------------------
        # Criterion 2 — Problem Sets category (10 + 10 points)
        # ------------------------------------------------------------------
        ps_found = result.get('problem_sets_found', False)
        ps_weight = _to_float(result.get('problem_sets_weight', 0))
        expected_ps_weight = _to_float(expected_categories.get('Problem Sets', 30))
        # Tolerance: ±6 absolute (works for both % values like 30 and
        # decimal fraction values like 0.30 mapped through * 100 by UI)
        ps_tol = 6.0

        if ps_found:
            score += 10
            subscores['problem_sets_exists'] = True
            feedback_parts.append("Problem Sets category: exists [10/10]")
        else:
            subscores['problem_sets_exists'] = False
            feedback_parts.append("Problem Sets category: NOT FOUND [0/10]")

        if ps_found and abs(ps_weight - expected_ps_weight) <= ps_tol:
            score += 10
            subscores['problem_sets_weight_correct'] = True
            feedback_parts.append(
                f"Problem Sets weight: {ps_weight} (expected {expected_ps_weight}±{ps_tol}) [10/10]"
            )
        elif ps_found and ps_weight > 0:
            score += 4
            subscores['problem_sets_weight_correct'] = False
            feedback_parts.append(
                f"Problem Sets weight: {ps_weight} (expected {expected_ps_weight}±{ps_tol}) [4/10]"
            )
        else:
            subscores['problem_sets_weight_correct'] = False
            if ps_found:
                feedback_parts.append(
                    f"Problem Sets weight: {ps_weight} (expected {expected_ps_weight}) [0/10]"
                )
            else:
                feedback_parts.append("Problem Sets weight: N/A (category missing) [0/10]")

        # ------------------------------------------------------------------
        # Criterion 3 — Lab Reports category (10 + 10 points)
        # ------------------------------------------------------------------
        lr_found = result.get('lab_reports_found', False)
        lr_weight = _to_float(result.get('lab_reports_weight', 0))
        expected_lr_weight = _to_float(expected_categories.get('Lab Reports', 30))
        lr_tol = 6.0

        if lr_found:
            score += 10
            subscores['lab_reports_exists'] = True
            feedback_parts.append("Lab Reports category: exists [10/10]")
        else:
            subscores['lab_reports_exists'] = False
            feedback_parts.append("Lab Reports category: NOT FOUND [0/10]")

        if lr_found and abs(lr_weight - expected_lr_weight) <= lr_tol:
            score += 10
            subscores['lab_reports_weight_correct'] = True
            feedback_parts.append(
                f"Lab Reports weight: {lr_weight} (expected {expected_lr_weight}±{lr_tol}) [10/10]"
            )
        elif lr_found and lr_weight > 0:
            score += 4
            subscores['lab_reports_weight_correct'] = False
            feedback_parts.append(
                f"Lab Reports weight: {lr_weight} (expected {expected_lr_weight}±{lr_tol}) [4/10]"
            )
        else:
            subscores['lab_reports_weight_correct'] = False
            if lr_found:
                feedback_parts.append(
                    f"Lab Reports weight: {lr_weight} (expected {expected_lr_weight}) [0/10]"
                )
            else:
                feedback_parts.append("Lab Reports weight: N/A (category missing) [0/10]")

        # ------------------------------------------------------------------
        # Criterion 4 — Exams category (10 + 10 points)
        # ------------------------------------------------------------------
        ex_found = result.get('exams_found', False)
        ex_weight = _to_float(result.get('exams_weight', 0))
        expected_ex_weight = _to_float(expected_categories.get('Exams', 40))
        ex_tol = 6.0

        if ex_found:
            score += 10
            subscores['exams_exists'] = True
            feedback_parts.append("Exams category: exists [10/10]")
        else:
            subscores['exams_exists'] = False
            feedback_parts.append("Exams category: NOT FOUND [0/10]")

        if ex_found and abs(ex_weight - expected_ex_weight) <= ex_tol:
            score += 10
            subscores['exams_weight_correct'] = True
            feedback_parts.append(
                f"Exams weight: {ex_weight} (expected {expected_ex_weight}±{ex_tol}) [10/10]"
            )
        elif ex_found and ex_weight > 0:
            score += 4
            subscores['exams_weight_correct'] = False
            feedback_parts.append(
                f"Exams weight: {ex_weight} (expected {expected_ex_weight}±{ex_tol}) [4/10]"
            )
        else:
            subscores['exams_weight_correct'] = False
            if ex_found:
                feedback_parts.append(
                    f"Exams weight: {ex_weight} (expected {expected_ex_weight}) [0/10]"
                )
            else:
                feedback_parts.append("Exams weight: N/A (category missing) [0/10]")

        # ------------------------------------------------------------------
        # Criterion 5 — Exams sub-weights: Midterm (5 pts) + Final (5 pts)
        # ------------------------------------------------------------------
        midterm_weight = _to_float(result.get('midterm_weight', 0))
        final_weight = _to_float(result.get('final_weight', 0))
        expected_midterm = _to_float(expected_subweights.get('Midterm Exam', 40))
        expected_final = _to_float(expected_subweights.get('Final Exam', 60))
        sub_tol = 8.0

        if abs(midterm_weight - expected_midterm) <= sub_tol:
            score += 5
            subscores['midterm_weight_correct'] = True
            feedback_parts.append(
                f"Midterm Exam weight within Exams: {midterm_weight} "
                f"(expected {expected_midterm}±{sub_tol}) [5/5]"
            )
        elif midterm_weight > 0:
            score += 2
            subscores['midterm_weight_correct'] = False
            feedback_parts.append(
                f"Midterm Exam weight within Exams: {midterm_weight} "
                f"(expected {expected_midterm}±{sub_tol}) [2/5]"
            )
        else:
            subscores['midterm_weight_correct'] = False
            feedback_parts.append(
                f"Midterm Exam weight: {midterm_weight} (expected {expected_midterm}) [0/5]"
            )

        if abs(final_weight - expected_final) <= sub_tol:
            score += 5
            subscores['final_weight_correct'] = True
            feedback_parts.append(
                f"Final Exam weight within Exams: {final_weight} "
                f"(expected {expected_final}±{sub_tol}) [5/5]"
            )
        elif final_weight > 0:
            score += 2
            subscores['final_weight_correct'] = False
            feedback_parts.append(
                f"Final Exam weight within Exams: {final_weight} "
                f"(expected {expected_final}±{sub_tol}) [2/5]"
            )
        else:
            subscores['final_weight_correct'] = False
            feedback_parts.append(
                f"Final Exam weight: {final_weight} (expected {expected_final}) [0/5]"
            )

        # ------------------------------------------------------------------
        # Bonus diagnostic: report how many items were moved into sub-cats
        # ------------------------------------------------------------------
        items_moved = int(result.get('items_in_correct_categories', 0))
        feedback_parts.append(
            f"Grade items moved into sub-categories: {items_moved}/6"
        )

        # ------------------------------------------------------------------
        # Pass determination
        # threshold: score >= 60 AND top-level aggregation must be correct
        # ------------------------------------------------------------------
        passed = (
            score >= 60
            and subscores.get('top_aggregation_correct', False)
        )

        logger.info(
            "Score: %d/100 | Passed: %s | Subscores: %s",
            score, passed, subscores
        )

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "Result file not found (/tmp/repair_gradebook_structure_result.json) — "
                "the export script may not have run or the file was not copied out of the VM"
            ),
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}",
        }
    except Exception as e:
        logger.error("Verification error: %s", e, exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
        }
