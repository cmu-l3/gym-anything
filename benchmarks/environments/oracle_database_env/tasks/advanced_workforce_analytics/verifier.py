"""
Verifier for advanced_workforce_analytics task.

Scoring breakdown (100 pts total):
- Report file exists on Desktop (10 pts)
- File has >= 10 non-blank lines (5 pts)
- All 4 question labels present (Q1-Q4) (4 × 3 pts = 12 pts)
- Q1 correct city identified (15 pts) / partial match (7 pts)
- Q2 correct manager identified (15 pts) / partial match (7 pts)
- Q3 salary increase percentage is a plausible number (10 pts) / close to ground truth (5 bonus)
- Q4 correct job title identified (15 pts) / partial match (7 pts)
- Report quality: structured output with labels and numeric values (8 pts)

Pass threshold: 50 pts
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(val, expected, tolerance_pct=10):
    """Check if a numeric value is within tolerance_pct% of expected."""
    if expected is None or val is None:
        return False
    if expected == 0:
        return abs(val) < 1.0
    return abs(val - expected) / abs(expected) * 100 <= tolerance_pct


def verify_advanced_workforce_analytics(traj, env_info, task_info):
    """
    Verifies the advanced_workforce_analytics task.
    Agent must answer 4 workforce analytics questions and save results to a file.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "score": 0.0,
            "passed": False,
            "feedback": "copy_from_env not available"
        }

    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "advanced_workforce_analytics_result.json")
        try:
            copy_from_env("/tmp/advanced_workforce_analytics_result.json", result_path)
        except Exception as e:
            return {
                "score": 0.0,
                "passed": False,
                "feedback": f"Could not retrieve result file: {e}"
            }

        if not os.path.exists(result_path):
            return {"score": 0.0, "passed": False, "feedback": "Result file not found after copy."}

        try:
            with open(result_path, "r") as f:
                result = json.load(f)
        except json.JSONDecodeError as e:
            return {"score": 0.0, "passed": False, "feedback": f"Result JSON malformed: {e}"}

    # Retrieve ground truth from task_info metadata (pre-computed) or from result
    metadata = task_info.get("metadata", {})
    ground_truth = result.get("ground_truth", {})

    # Expected answers (from metadata as primary, ground_truth as fallback)
    expected_q1_city = metadata.get("expected_q1_city", ground_truth.get("q1", {}).get("city", "Seattle"))
    expected_q2_manager = metadata.get("expected_q2_manager", ground_truth.get("q2", {}).get("manager_name", "Steven King"))
    expected_q2_count = metadata.get("expected_q2_report_count", ground_truth.get("q2", {}).get("report_count", 14))
    expected_q4_title = metadata.get("expected_q4_job_title", ground_truth.get("q4", {}).get("job_title", "Stock Clerk"))

    # Ground truth computed in setup for Q1 salary and Q3 pct
    gt_q1_salary = ground_truth.get("q1", {}).get("avg_salary")
    gt_q3_pct = ground_truth.get("q3", {}).get("avg_salary_increase_pct")

    score = 0
    feedback_parts = []

    # --- Report file exists (10 pts) ---
    if result.get("report_file_exists"):
        file_size = result.get("report_file_size", 0)
        score += 10
        feedback_parts.append(f"workforce_analytics_report.txt: exists ({file_size} bytes) (+10)")
    else:
        feedback_parts.append("workforce_analytics_report.txt: NOT found at /home/ga/Desktop/ (0 pts)")
        return {
            "score": 0.0,
            "passed": False,
            "feedback": " | ".join(feedback_parts)
        }

    # --- File quality: >= 10 lines (5 pts) ---
    line_count = result.get("report_line_count", 0)
    if line_count >= 10:
        score += 5
        feedback_parts.append(f"File content: {line_count} lines (>=10) (+5)")
    elif line_count >= 4:
        score += 2
        feedback_parts.append(f"File content: {line_count} lines (minimal) (+2)")
    else:
        feedback_parts.append(f"File content: only {line_count} lines (0 pts)")

    # --- Question labels (3 pts each × 4 = 12 pts) ---
    for q, has in [("Q1", result.get("has_q1_label")),
                    ("Q2", result.get("has_q2_label")),
                    ("Q3", result.get("has_q3_label")),
                    ("Q4", result.get("has_q4_label"))]:
        if has:
            score += 3
            feedback_parts.append(f"{q} label: present (+3)")
        else:
            feedback_parts.append(f"{q} label: MISSING (0 pts)")

    # --- Q1: Correct city (15 pts for exact, 7 for partial) ---
    extracted_q1_city = result.get("extracted_q1_city")
    content = result.get("report_content", "").lower()
    q1_city_found = (
        extracted_q1_city and expected_q1_city.lower() in extracted_q1_city.lower()
    ) or (expected_q1_city.lower() in content)

    if q1_city_found:
        score += 15
        feedback_parts.append(f"Q1 city: '{expected_q1_city}' found in report (+15)")

        # Salary bonus (5 pts)
        extracted_q1_salary = result.get("extracted_q1_salary")
        if gt_q1_salary and extracted_q1_salary and _close_enough(extracted_q1_salary, gt_q1_salary, 5):
            score += 5
            feedback_parts.append(f"Q1 salary: {extracted_q1_salary} ≈ {gt_q1_salary} (+5 bonus)")
        elif gt_q1_salary:
            feedback_parts.append(f"Q1 salary: extracted={extracted_q1_salary}, expected≈{gt_q1_salary} (no bonus)")
    else:
        # Check for any city mention
        any_city = bool(re.search(r'\b[A-Z][a-z]+ [A-Z][a-z]+\b|\b[A-Z][a-z]{4,}\b', result.get("report_content", "")))
        if any_city:
            score += 7
            feedback_parts.append(f"Q1 city: expected '{expected_q1_city}' not found, but city-like text present (+7 partial)")
        else:
            feedback_parts.append(f"Q1 city: '{expected_q1_city}' not found in report (0 pts)")

    # --- Q2: Correct manager (15 pts for exact, 7 for partial) ---
    extracted_q2_manager = result.get("extracted_q2_manager")
    q2_manager_found = (
        extracted_q2_manager and expected_q2_manager.lower() in extracted_q2_manager.lower()
    ) or (expected_q2_manager.lower() in content)

    if q2_manager_found:
        score += 15
        feedback_parts.append(f"Q2 manager: '{expected_q2_manager}' found (+15)")

        # Count bonus (5 pts)
        extracted_count = result.get("extracted_q2_count")
        if extracted_count and abs(extracted_count - expected_q2_count) <= 2:
            score += 5
            feedback_parts.append(f"Q2 report count: {extracted_count} ≈ {expected_q2_count} (+5 bonus)")
    else:
        # Any manager name mentioned?
        manager_names = ["King", "Kochhar", "De Haan", "Hartstein", "Baer", "Higgins", "Greenberg"]
        any_manager = any(n.lower() in content for n in manager_names)
        if any_manager:
            score += 7
            feedback_parts.append(f"Q2 manager: '{expected_q2_manager}' not found, but manager name present (+7 partial)")
        else:
            feedback_parts.append(f"Q2 manager: '{expected_q2_manager}' not found (0 pts)")

    # --- Q3: Salary increase percentage (10 pts) ---
    extracted_q3 = result.get("extracted_q3_pct")
    # Any plausible percentage number present
    pct_in_content = bool(re.search(r'-?\d+\.?\d*\s*%', result.get("report_content", "")))
    if extracted_q3 is not None:
        score += 10
        feedback_parts.append(f"Q3 avg salary increase: {extracted_q3}% found (+10)")
        if gt_q3_pct is not None and _close_enough(extracted_q3, gt_q3_pct, 15):
            score += 5
            feedback_parts.append(f"Q3 value close to expected {gt_q3_pct}% (+5 bonus)")
    elif pct_in_content:
        score += 5
        feedback_parts.append("Q3: percentage number found in report (+5 partial)")
    else:
        feedback_parts.append("Q3: no percentage value found in report (0 pts)")

    # --- Q4: Most mobile job title (15 pts for exact, 7 for partial) ---
    q4_title_found = expected_q4_title.lower() in content
    if q4_title_found:
        score += 15
        feedback_parts.append(f"Q4 job title: '{expected_q4_title}' found (+15)")
    else:
        # Any job title mention
        job_titles = ["clerk", "representative", "manager", "programmer", "accountant", "analyst"]
        any_title = any(t in content for t in job_titles)
        if any_title:
            score += 7
            feedback_parts.append(f"Q4: '{expected_q4_title}' not found, but job title text present (+7 partial)")
        else:
            feedback_parts.append(f"Q4: '{expected_q4_title}' not found (0 pts)")

    # --- Report structure quality (8 pts) ---
    has_numbers = bool(re.search(r'\d{3,}', result.get("report_content", "")))
    has_all_labels = all([result.get(f"has_q{i}_label") for i in range(1, 5)])
    if has_numbers and has_all_labels:
        score += 8
        feedback_parts.append("Report structure: has all labels and numeric values (+8)")
    elif has_numbers or has_all_labels:
        score += 3
        feedback_parts.append("Report structure: partially structured (+3)")

    max_score = 100  # 10+5+12+15+5+15+5+10+5+15+8 = 105 possible with bonuses, cap at 100
    capped_score = min(score, max_score)
    normalized = round(capped_score / max_score, 4)
    passed = capped_score >= 50

    return {
        "score": normalized,
        "passed": passed,
        "raw_score": capped_score,
        "max_score": max_score,
        "feedback": " | ".join(feedback_parts)
    }
