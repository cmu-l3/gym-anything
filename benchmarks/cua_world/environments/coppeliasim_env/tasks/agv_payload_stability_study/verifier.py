#!/usr/bin/env python3
"""
Verifier for agv_payload_stability_study task.

Scoring (100 points):
  - Criterion 1 (20 pts): Both CSV and JSON files exist and were created after task start.
  - Criterion 2 (20 pts): CSV contains >= 8 rows and has the required columns.
  - Criterion 3 (30 pts): Stability transition found. CSV shows at least one tipped=True 
                          and at least one tipped=False trial.
  - Criterion 4 (30 pts): Physics Plausibility. The reported `max_safe_acceleration_m_s2` 
                          must fall in [2.5, 4.0] (theoretical threshold is ~3.27 m/s^2).

Pass threshold: 70
Anti-gaming checks:
  - Do-nothing score: 0 (no files exist before task start).
  - Fake data: Random/fake thresholds will likely fail the physics plausibility boundary (2.5 to 4.0).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/agv_payload_stability_result.json"

def verify_agv_payload_stability_study(traj, env_info, task_info):
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

    # Criterion 1: Files exist and are new (20 pts)
    files_ok = False
    if result.get("csv_exists") and result.get("json_exists"):
        if result.get("csv_is_new") and result.get("json_is_new"):
            score += 20
            files_ok = True
            feedback.append("Both output files created after task start (+20)")
        else:
            feedback.append("Files exist but one or both predate task start (stale files)")
    else:
        feedback.append("One or both output files (CSV/JSON) not found")

    # Criterion 2: CSV Completeness (20 pts)
    csv_stats = result.get("csv_stats", {})
    if isinstance(csv_stats, dict):
        row_count = int(csv_stats.get("row_count", 0))
        has_req_cols = csv_stats.get("has_req_cols", False)
        
        if row_count >= 8 and has_req_cols:
            score += 20
            feedback.append(f"CSV data complete: {row_count} trials recorded (+20)")
        elif row_count > 0:
            score += 10
            feedback.append(f"CSV has {row_count} trials, required_cols={has_req_cols} (partial: 10/20)")
        else:
            feedback.append("CSV is empty or missing required columns")
    else:
        feedback.append("Could not parse CSV statistics")

    # Criterion 3: Stability transition found (30 pts)
    if isinstance(csv_stats, dict):
        has_true = csv_stats.get("has_true", False)
        has_false = csv_stats.get("has_false", False)
        
        if has_true and has_false:
            score += 30
            feedback.append("CSV captures both stable and unstable trials (+30)")
        elif has_true or has_false:
            score += 10
            feedback.append("CSV only shows one state (all stable or all tipped) (partial: 10/30)")
        else:
            feedback.append("CSV missing valid Boolean tipped data")

    # Criterion 4: Physics Plausibility (30 pts)
    json_info = result.get("json_info", {})
    if isinstance(json_info, dict):
        has_fields = json_info.get("has_fields", False)
        max_safe = float(json_info.get("max_safe", 0.0))
        
        if has_fields:
            if 2.5 <= max_safe <= 4.0:
                score += 30
                feedback.append(f"Physics Plausibility passed: max_safe={max_safe} m/s^2 is within expected theoretical bounds [2.5, 4.0] (+30)")
            elif max_safe > 0:
                score += 10
                feedback.append(f"Physics Plausibility failed: max_safe={max_safe} m/s^2 falls outside [2.5, 4.0] boundary (partial: 10/30)")
            else:
                feedback.append(f"Report JSON indicates invalid max_safe threshold: {max_safe}")
        else:
            feedback.append("Report JSON missing required fields (max_safe_acceleration_m_s2, etc.)")
    else:
        feedback.append("Could not parse JSON report fields")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }