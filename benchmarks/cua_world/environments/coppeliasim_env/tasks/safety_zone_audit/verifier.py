#!/usr/bin/env python3
"""
Verifier for safety_zone_audit task.
Checks programmatic metrics over the output data structures and checks for correct geometric math.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/safety_zone_audit_result.json"

def verify_safety_zone_audit(traj, env_info, task_info):
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

    csv_exists = result.get("csv_exists")
    csv_is_new = result.get("csv_is_new")
    csv_row_count = int(result.get("csv_row_count", 0))
    csv_analysis = result.get("csv_analysis", {})

    json_exists = result.get("json_exists")
    json_is_new = result.get("json_is_new")
    json_fields = result.get("json_fields", {})

    # Criterion 1: CSV exists and is new (15 pts)
    if csv_exists and csv_is_new:
        score += 15
        feedback.append("CSV created after task start (+15)")
    elif csv_exists:
        feedback.append("CSV exists but predates task start (stale file)")
    else:
        feedback.append("safety_zone_log.csv not found")

    # Criterion 2: CSV has >= 100 rows (15 pts)
    if csv_row_count >= 100:
        score += 15
        feedback.append(f"CSV has {csv_row_count} rows (>= 100 required) (+15)")
    elif csv_row_count >= 50:
        score += 7
        feedback.append(f"CSV has {csv_row_count} rows (partial: 7/15)")
    else:
        feedback.append(f"CSV has {csv_row_count} rows (need >= 100)")

    # Criterion 3: >= 6 distinct profiles (15 pts)
    num_profiles = int(csv_analysis.get("num_profiles", 0))
    if num_profiles >= 6:
        score += 15
        feedback.append(f"Tested {num_profiles} motion profiles (>= 6 required) (+15)")
    elif num_profiles >= 3:
        score += 7
        feedback.append(f"Tested {num_profiles} motion profiles (partial: 7/15)")
    else:
        feedback.append(f"Tested {num_profiles} motion profiles (need >= 6)")

    # Criterion 4: Geometric correctness of violations (15 pts)
    valid_rows = int(csv_analysis.get("valid_rows", 0))
    geo_correct = int(csv_analysis.get("geo_correct_count", 0))
    if valid_rows > 0:
        geo_pct = geo_correct / valid_rows
        if geo_pct >= 0.9:
            score += 15
            feedback.append(f"Violation flags geometrically correct ({geo_pct*100:.1f}%) (+15)")
        elif geo_pct >= 0.7:
            score += 7
            feedback.append(f"Violation flags partially correct ({geo_pct*100:.1f}%) (partial: 7/15)")
        else:
            feedback.append(f"Violation flags incorrect ({geo_pct*100:.1f}% correct)")
    else:
        feedback.append("No valid row data to verify geometric correctness")

    # Criterion 5: JSON report exists, new, has required fields (15 pts)
    has_fields = json_fields.get("has_fields", False)
    if json_exists and json_is_new and has_fields:
        score += 15
        feedback.append("Compliance report JSON is valid with required fields (+15)")
    elif json_exists and json_is_new:
        score += 7
        feedback.append("Compliance report JSON exists but missing required fields (partial: 7/15)")
    else:
        feedback.append("safety_compliance_report.json not found or not new")

    # Criterion 6: Cross-validate JSON and CSV (15 pts)
    json_steps = int(json_fields.get("total_steps_monitored", -1))
    json_violations = int(json_fields.get("total_violations", -1))
    csv_violations = int(csv_analysis.get("violations_count", 0))

    cv_score = 0
    if json_exists and json_is_new and has_fields:
        if abs(json_steps - valid_rows) <= 5 and json_steps > 0:
            cv_score += 7
            feedback.append(f"JSON total_steps matches CSV rows ({json_steps}) (+7)")
        else:
            feedback.append(f"JSON total_steps ({json_steps}) mismatches CSV ({valid_rows})")

        if abs(json_violations - csv_violations) <= 2 and json_steps > 0:
            cv_score += 8
            feedback.append(f"JSON total_violations matches CSV count ({json_violations}) (+8)")
        else:
            feedback.append(f"JSON total_violations ({json_violations}) mismatches CSV ({csv_violations})")
    else:
        feedback.append("Cannot cross-validate without valid JSON report")
    
    score += cv_score

    # Criterion 7: Spatial diversity (10 pts)
    x_range = float(csv_analysis.get("x_range", 0.0))
    y_range = float(csv_analysis.get("y_range", 0.0))
    z_range = float(csv_analysis.get("z_range", 0.0))
    ranges = [x_range, y_range, z_range]
    axes_diverse = sum(1 for r in ranges if r >= 0.15)

    if axes_diverse >= 2:
        score += 10
        feedback.append(f"Positions are spatially diverse (>= 0.15m in {axes_diverse} axes) (+10)")
    elif axes_diverse == 1:
        score += 5
        feedback.append(f"Positions have limited diversity (>= 0.15m in {axes_diverse} axis) (partial: 5/10)")
    else:
        feedback.append("End-effector positions lack spatial diversity")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }