#!/usr/bin/env python3
"""
Verifier for pid_joint_tuning_study task.

Scoring (100 points):
  - Criterion 1 (15 pts): pid_tuning_data.csv exists and was created after task start
  - Criterion 2 (20 pts): CSV has >= 8 trial rows
  - Criterion 3 (20 pts): Valid metric columns (>= 6 rows have plausible step response metrics)
  - Criterion 4 (15 pts): Gain diversity (P-gain range >= 0.5 AND >= 3 distinct overshoot values)
  - Criterion 5 (15 pts): JSON report valid (has required fields, total_trials >= 8)
  - Criterion 6 (15 pts): JSON-CSV consistency (best_trial_id exists in CSV and gains match)

Pass threshold: 70
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/pid_tuning_result.json"

def verify_pid_tuning(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # Criterion 1: CSV exists and is new (15 pts)
    if result.get("csv_exists") and result.get("csv_is_new"):
        score += 15
        feedback.append("CSV file created after task start (+15)")
    elif result.get("csv_exists"):
        feedback.append("CSV exists but was not created after task start (stale file)")
    else:
        feedback.append("pid_tuning_data.csv not found")

    # Criterion 2: >= 8 rows (20 pts)
    row_count = int(result.get("csv_row_count", 0))
    if row_count >= 8:
        score += 20
        feedback.append(f"CSV has {row_count} trials (>= 8 required) (+20)")
    elif row_count >= 4:
        score += 10
        feedback.append(f"CSV has only {row_count} trials (partial: 10/20)")
    else:
        feedback.append(f"CSV has {row_count} trials (need >= 8)")

    # Criterion 3: Valid metric columns (20 pts)
    csv_analysis = result.get("csv_analysis", {})
    if isinstance(csv_analysis, dict):
        has_columns = csv_analysis.get("has_columns", False)
        valid_rows = int(csv_analysis.get("valid_metric_rows", 0))
        if has_columns and valid_rows >= 6:
            score += 20
            feedback.append(f"Valid metrics computed for {valid_rows} trials (+20)")
        elif has_columns and valid_rows >= 3:
            score += 10
            feedback.append(f"Valid metrics computed for {valid_rows} trials (partial: 10/20)")
        elif not has_columns:
            feedback.append("CSV lacks one or more required metric columns")
        else:
            feedback.append(f"Insufficient valid metrics: only {valid_rows} rows")
    else:
        feedback.append("Could not parse CSV analysis")

    # Criterion 4: Gain diversity (15 pts)
    if isinstance(csv_analysis, dict):
        kp_range = float(csv_analysis.get("kp_range", 0.0))
        dist_overshoots = int(csv_analysis.get("distinct_overshoots", 0))
        if kp_range >= 0.5 and dist_overshoots >= 3:
            score += 15
            feedback.append(f"Gain diversity excellent (kp range {kp_range:.2f}, {dist_overshoots} dist. overshoots) (+15)")
        elif kp_range >= 0.1 and dist_overshoots >= 2:
            score += 5
            feedback.append(f"Gain diversity marginal (kp range {kp_range:.2f}, {dist_overshoots} dist. overshoots) (partial: 5/15)")
        else:
            feedback.append(f"Poor gain diversity (kp range {kp_range:.2f}, {dist_overshoots} dist. overshoots)")

    # Criterion 5: JSON valid (15 pts)
    json_info = result.get("json_info", {})
    if isinstance(json_info, dict):
        has_fields = json_info.get("has_fields", False)
        total_trials = int(json_info.get("total_trials", 0))
        if result.get("json_exists") and result.get("json_is_new") and has_fields and total_trials >= 8:
            score += 15
            feedback.append(f"JSON report valid with {total_trials} trials (+15)")
        elif result.get("json_exists") and result.get("json_is_new") and has_fields:
            score += 5
            feedback.append(f"JSON report valid but total_trials={total_trials} (partial: 5/15)")
        elif result.get("json_exists") and result.get("json_is_new"):
            feedback.append("JSON report lacks required fields")
        else:
            feedback.append("pid_tuning_report.json not found or not new")

    # Criterion 6: JSON-CSV consistency (15 pts)
    if isinstance(json_info, dict) and isinstance(csv_analysis, dict):
        best_id = json_info.get("best_trial_id", "")
        trials = csv_analysis.get("trials", {})
        if str(best_id) and str(best_id) in trials:
            csv_kp = float(trials[str(best_id)].get("kp", -1))
            csv_ki = float(trials[str(best_id)].get("ki", -1))
            csv_kd = float(trials[str(best_id)].get("kd", -1))

            j_kp = float(json_info.get("best_kp", -2))
            j_ki = float(json_info.get("best_ki", -2))
            j_kd = float(json_info.get("best_kd", -2))

            if abs(csv_kp - j_kp) < 0.01 and abs(csv_ki - j_ki) < 0.01 and abs(csv_kd - j_kd) < 0.01:
                score += 15
                feedback.append(f"JSON best_trial_id '{best_id}' gains match CSV (+15)")
            else:
                feedback.append(f"JSON gains for best_trial_id '{best_id}' do not match CSV")
        else:
            feedback.append(f"JSON best_trial_id '{best_id}' not found in CSV")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }