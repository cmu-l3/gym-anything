#!/usr/bin/env python3
"""
Verifier for Payload Limit & Joint Torque Validation.

Scoring (100 points max):
  1. File Generation (15 pts): Output CSV & JSON exist and are new.
  2. Data Volume (15 pts): CSV has >= 15 rows of data.
  3. Physics Integrity (40 pts): Strong positive correlation between mass & torque (>0.95),
                                 and base torque at 1kg falls into physically accurate UR5 range (20-80 Nm).
  4. Limit Accuracy (15 pts): The `exceeds_limit` boolean matches `torque > 150.0` mathematically.
  5. JSON Summary (15 pts): JSON has all required fields and correct limit (150.0 Nm).

CRITICAL: If the 'Physics Integrity' check fails, the task will not pass regardless of other points,
as this signifies the data is fabricated or the simulation physics were improperly executed.
Pass threshold: 70
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/payload_torque_validation_result.json"

def verify_payload_torque_validation(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result data: {e}"}
    finally:
        if os.path.exists(tmp.name):
            try:
                os.unlink(tmp.name)
            except Exception:
                pass

    score = 0
    feedback = []

    # If script crashed internally, report it
    if result.get("error"):
        feedback.append(f"Export script encountered an error: {result['error']}")

    # 1. File Generation (15 pts)
    csv_ok = result.get("csv_exists") and result.get("csv_is_new")
    json_ok = result.get("json_exists") and result.get("json_is_new")
    
    if csv_ok and json_ok:
        score += 15
        feedback.append("Both output files exist and were created during task (+15)")
    elif result.get("csv_exists") or result.get("json_exists"):
        score += 5
        feedback.append("Output files exist but some are stale/missing (partial: 5/15)")
    else:
        feedback.append("No output files found")

    # 2. Data Volume (15 pts)
    rows = result.get("csv_rows", 0)
    if rows >= 15:
        score += 15
        feedback.append(f"CSV contains {rows} records (>= 15 required) (+15)")
    elif rows >= 5:
        score += 5
        feedback.append(f"CSV contains {rows} records (partial: 5/15)")
    else:
        feedback.append(f"CSV contains {rows} records (need >= 15)")

    # 3. Physics Integrity (40 pts)
    physics_valid = result.get("physics_valid", False)
    corr = result.get("correlation", 0.0)
    t_1kg = result.get("torque_at_1kg", 0.0)
    
    if physics_valid:
        score += 40
        feedback.append(f"Physics Valid: Strong mass/torque correlation (r={corr:.3f}) and plausible base torque at 1kg ({t_1kg:.1f} Nm) (+40)")
    else:
        feedback.append(f"Physics Invalid: r={corr:.3f} (need >0.95), torque@1kg={t_1kg:.1f} Nm (need 20-80 Nm). Check simulation stability.")

    # 4. Limit Accuracy (15 pts)
    if result.get("flags_correct", False):
        score += 15
        feedback.append("Limit exceedance flags correctly match math (torque > 150.0 Nm) (+15)")
    else:
        feedback.append("Limit exceedance flags are incorrect or column is missing")

    # 5. JSON Summary (15 pts)
    if result.get("json_valid", False):
        score += 15
        feedback.append("JSON summary is valid and correctly specifies the 150.0 limit (+15)")
    else:
        feedback.append("JSON summary is missing required fields or has incorrect limit data")

    # Final pass logic: Strict requirement on physics valid to prevent faking the CSV
    passed = (score >= 70) and physics_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }