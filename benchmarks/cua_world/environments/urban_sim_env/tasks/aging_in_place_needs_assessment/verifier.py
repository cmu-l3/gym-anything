#!/usr/bin/env python3
"""Verifier for aging_in_place_needs_assessment task."""

import json
import tempfile
import os
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aging_in_place(traj, env_info, task_info):
    """
    Verify aging in place analysis was completed accurately.
    Scoring System:
    - 15 pts: Notebook Executed
    - 15 pts: CSV Structure Valid (exists, 20 rows, correct columns)
    - 35 pts: Data Logic Validation (CSV mathematical consistency, percentages in [0,1])
    - 20 pts: JSON Summary Valid (exists, correct keys, realistic values)
    - 15 pts: Scatter Plot Generated (exists, reasonable size)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_columns = metadata.get('expected_csv_columns', ["zone_id", "total_senior_hhs", "pct_low_income", "pct_overhoused", "vulnerability_score"])
    expected_json_keys = metadata.get('expected_json_keys', ["city_total_senior_hhs", "city_pct_low_income_seniors", "city_pct_overhoused_seniors"])

    score = 0
    feedback = []

    # Read base task result from the export script
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result metadata: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Criterion 1: Notebook Executed (15 pts)
    nb_a = result.get('notebook_analysis', {})
    if result.get('notebook_exists') and nb_a.get('num_executed_cells', 0) >= 3:
        score += 15
        feedback.append("Notebook executed successfully")
    elif result.get('notebook_exists') and nb_a.get('num_executed_cells', 0) > 0:
        score += 5
        feedback.append("Notebook partially executed")

    # Fetch CSV for validation
    csv_valid = False
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/home/ga/urbansim_projects/output/senior_vulnerability_top20.csv", temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            reader = csv.reader(f)
            header = next(reader, [])
            rows = list(reader)

            header_clean = [h.strip().lower() for h in header]
            has_expected_cols = all(col.lower() in header_clean for col in expected_csv_columns)

            # Criterion 2: CSV Structure Valid (15 pts)
            if has_expected_cols and len(rows) == 20:
                score += 15
                csv_valid = True
                feedback.append("CSV structure valid (20 rows, expected columns)")
            else:
                if has_expected_cols:
                    score += 5
                    feedback.append(f"CSV has correct columns but wrong row count ({len(rows)} instead of 20)")
                elif len(rows) == 20:
                    score += 5
                    feedback.append("CSV has 20 rows but missing expected columns")

            # Criterion 3: Data Logic Validation (35 pts)
            if csv_valid:
                idx_low_inc = header_clean.index("pct_low_income")
                idx_overhoused = header_clean.index("pct_overhoused")
                idx_score = header_clean.index("vulnerability_score")

                math_correct = True
                bounds_correct = True

                for row in rows:
                    try:
                        pct_l = float(row[idx_low_inc])
                        pct_o = float(row[idx_overhoused])
                        v_score = float(row[idx_score])

                        if not (0.0 <= pct_l <= 1.0) or not (0.0 <= pct_o <= 1.0):
                            bounds_correct = False
                        
                        # Tolerance for floating point
                        if abs((pct_l + pct_o) - v_score) > 0.01:
                            math_correct = False
                    except (ValueError, IndexError):
                        math_correct = False
                        bounds_correct = False
                        break

                if math_correct and bounds_correct:
                    score += 35
                    feedback.append("CSV Data logic valid (math matches, values in bounds)")
                else:
                    if math_correct:
                        score += 15
                        feedback.append("CSV math matches, but percentages out of bounds [0,1]")
                    elif bounds_correct:
                        score += 15
                        feedback.append("CSV percentages in bounds, but score math (pct_low + pct_over) is incorrect")
                    else:
                        feedback.append("CSV data logic failed (math incorrect, out of bounds)")

    except Exception as e:
        feedback.append(f"CSV validation failed: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Fetch JSON for validation
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/home/ga/urbansim_projects/output/senior_summary.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            summary = json.load(f)

        # Criterion 4: JSON Summary Valid (20 pts)
        has_keys = all(k in summary for k in expected_json_keys)
        if has_keys:
            score += 10
            
            # Sanity checks for city-wide SF data
            tot_hhs = summary.get("city_total_senior_hhs", 0)
            pct_low = summary.get("city_pct_low_income_seniors", -1)
            pct_over = summary.get("city_pct_overhoused_seniors", -1)

            if isinstance(tot_hhs, (int, float)) and tot_hhs > 5000:
                if 0.0 <= pct_low <= 1.0 and 0.0 <= pct_over <= 1.0:
                    score += 10
                    feedback.append("JSON summary valid and values look realistic")
                else:
                    feedback.append("JSON summary has keys but percentages are out of [0,1] bounds")
            else:
                feedback.append("JSON summary has keys but total senior hhs count is unrealistically low/invalid")
        else:
            feedback.append("JSON summary missing required keys")

    except Exception as e:
        feedback.append(f"JSON validation failed: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Criterion 5: Scatter Plot Generated (15 pts)
    if result.get('plot_exists'):
        if result.get('plot_created'):
            if result.get('plot_size_kb', 0) >= 10:
                score += 15
                feedback.append("Plot generated successfully")
            else:
                score += 5
                feedback.append("Plot file generated but size is unusually small")
        else:
            feedback.append("Plot exists but was not created during this task")
    else:
        feedback.append("Plot file not found")

    passed = score >= 70 and csv_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }