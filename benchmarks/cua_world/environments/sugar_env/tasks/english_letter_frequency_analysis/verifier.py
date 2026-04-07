#!/usr/bin/env python3
"""Verifier for english_letter_frequency_analysis task.

Validates that the agent correctly processed a real book file to 
produce accurate, cleanly-formatted CSV statistics.
"""

import json
import os
import tempfile
import string

def verify_letter_frequency(traj, env_info, task_info):
    """Verifies the accuracy and structure of the letter frequency output."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/letter_freq_analysis.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    task_start = result.get("task_start", 0)

    # 1. Script existence and anti-gaming (10 pts)
    if result.get("script_exists") and result.get("script_size", 0) > 20:
        if result.get("script_mtime", 0) >= task_start:
            score += 10
            feedback.append("Python script created successfully.")
        else:
            score += 5
            feedback.append("Python script exists but mtime predates task start.")
    else:
        feedback.append("Python script missing or practically empty.")

    # 2. CSV existence and anti-gaming (10 pts)
    if result.get("csv_exists") and result.get("csv_size", 0) > 50:
        if result.get("csv_mtime", 0) >= task_start:
            score += 10
            feedback.append("CSV file generated successfully.")
        else:
            score += 5
            feedback.append("CSV file exists but mtime predates task start.")
    else:
        feedback.append("FAIL: CSV file missing or empty.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 3. CSV Header (5 pts)
    if result.get("csv_header_exact"):
        score += 5
        feedback.append("Exact header row match ('Letter,Count,Percentage').")
    else:
        feedback.append("Header row mismatch or missing.")

    # 4. Alphabet completeness (10 pts)
    csv_rows = result.get("csv_rows", [])
    letters_found = [r.get("letter", "").upper() for r in csv_rows]
    if len(csv_rows) == 26 and set(letters_found) == set(string.ascii_uppercase):
        score += 10
        feedback.append("Exactly 26 valid alphabet rows found.")
    else:
        feedback.append(f"Invalid row count or missing letters (found {len(csv_rows)} data rows).")

    # 5. Descending sort order by Count (15 pts)
    try:
        counts = [int(float(r.get("count", 0))) for r in csv_rows]
        if counts and all(counts[i] >= counts[i+1] for i in range(len(counts)-1)):
            score += 15
            feedback.append("Data correctly sorted in descending order.")
        else:
            feedback.append("Rows are NOT sorted by Count in descending order.")
    except ValueError:
        feedback.append("Could not verify sorting due to non-numeric counts.")

    # Extract dynamic GT and Agent mappings
    gt_counts = result.get("gt_counts", {})
    gt_percs = result.get("gt_percs", {})
    agent_data = {r.get("letter", "").upper(): r for r in csv_rows}

    # 6. Exact Count 'E' Validation (15 pts)
    exact_e_passed = False
    try:
        agent_e_count = int(float(agent_data.get("E", {}).get("count", -1)))
        gt_e_count = gt_counts.get("E", -2)
        if agent_e_count == gt_e_count and gt_e_count > 0:
            score += 15
            exact_e_passed = True
            feedback.append(f"Exact count for 'E' perfectly matches ground truth ({gt_e_count}).")
        else:
            feedback.append(f"Count for 'E' mismatch (Got: {agent_e_count}, Expected: {gt_e_count}).")
    except (ValueError, TypeError):
        feedback.append("Invalid count format for 'E'.")

    # 7. Exact Count 'Z' Validation (10 pts)
    try:
        agent_z_count = int(float(agent_data.get("Z", {}).get("count", -1)))
        gt_z_count = gt_counts.get("Z", -2)
        if agent_z_count == gt_z_count and gt_z_count > 0:
            score += 10
            feedback.append(f"Exact count for 'Z' perfectly matches ground truth ({gt_z_count}).")
        else:
            feedback.append(f"Count for 'Z' mismatch (Got: {agent_z_count}, Expected: {gt_z_count}).")
    except (ValueError, TypeError):
        feedback.append("Invalid count format for 'Z'.")

    # 8. Percentage Accuracy 'E' (15 pts)
    perc_e_passed = False
    try:
        agent_e_perc = float(agent_data.get("E", {}).get("perc", -1.0))
        gt_e_perc = gt_percs.get("E", -2.0)
        # Tolerance of 0.02 allows for minor rounding anomalies
        if abs(agent_e_perc - gt_e_perc) <= 0.02 and gt_e_perc > 0:
            score += 15
            perc_e_passed = True
            feedback.append(f"Percentage for 'E' is accurate ({agent_e_perc}%).")
        else:
            feedback.append(f"Percentage for 'E' mismatch (Got: {agent_e_perc}%, Expected: {gt_e_perc}%). Note: Punctuation/whitespace shouldn't be in the denominator.")
    except (ValueError, TypeError):
        feedback.append("Invalid percentage format for 'E'.")

    # 9. Percentage Sum (10 pts)
    try:
        total_perc = sum(float(r.get("perc", 0)) for r in csv_rows)
        if 99.9 <= total_perc <= 100.1:
            score += 10
            feedback.append(f"Percentage column sums cleanly to ~100% ({total_perc:.2f}%).")
        else:
            feedback.append(f"Percentage column does not sum to 100% (Sum: {total_perc:.2f}%).")
    except ValueError:
        feedback.append("Could not sum percentages due to non-numeric characters.")

    # Determine final success
    # Must get majority of structural points AND prove algorithmic success via 'E' metrics
    passed = score >= 75 and (exact_e_passed or perc_e_passed)

    if passed:
        feedback.append("SUCCESS: Script correctly processed full literary text.")
    else:
        feedback.append(f"FAILED: Final score {score}/100 with algorithmic proof criteria met: {exact_e_passed or perc_e_passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }