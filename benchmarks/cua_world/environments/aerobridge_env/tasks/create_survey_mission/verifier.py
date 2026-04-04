#!/usr/bin/env python3
"""Verifier for create_survey_mission task.

Checks that both required records were created:
  1. FlightPlan 'Kolkata Port Survey' with valid GeoJSON
  2. FlightOperation 'Kolkata Port Inspection' referencing the new plan,
     with correct drone (F1 #2)

Scoring (100 points total):
  - FlightPlan exists with correct name:        20 pts
  - FlightPlan has valid GeoJSON:               20 pts
  - FlightOperation exists with correct name:   20 pts
  - FlightOperation references NEW plan:        25 pts
  - FlightOperation drone is F1 #2:             15 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXISTING_PLAN_NAME = "Flight Plan A"
EXISTING_PLAN_ID = "12818e87-4c96-4e4c-8c63-82b8e12c3b73"
EXPECTED_DRONE_ID = "0450852f-856e-4ecb-beb6-01ccded8529d"  # F1 #2


def verify_create_survey_mission(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_path = tmp.name
    tmp.close()
    try:
        copy_from_env("/tmp/create_survey_mission_result.json", tmp_path)
        with open(tmp_path) as f:
            data = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    if data.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {data['error']}"}

    score = 0
    feedback_parts = []
    fp = data.get("flight_plan")
    fo = data.get("flight_operation")

    # ── Check 1: FlightPlan exists (20 pts) ───────────────────────────────────
    if fp and fp.get("name", "").strip().lower() == "kolkata port survey":
        score += 20
        feedback_parts.append("✓ FlightPlan 'Kolkata Port Survey' created (+20)")
    elif fp:
        score += 10
        feedback_parts.append(
            f"~ FlightPlan found but name mismatch: '{fp.get('name')}' (+10)"
        )
    else:
        feedback_parts.append("✗ FlightPlan 'Kolkata Port Survey' not found")

    # ── Check 2: FlightPlan has valid GeoJSON (20 pts) ────────────────────────
    if fp:
        geo_str = fp.get("geo_json", "")
        geo_valid = False
        if geo_str and len(geo_str) > 10:
            try:
                geo_obj = json.loads(geo_str) if isinstance(geo_str, str) else geo_str
                if isinstance(geo_obj, dict) and "type" in geo_obj:
                    geo_valid = True
            except Exception:
                pass
        if geo_valid:
            score += 20
            feedback_parts.append("✓ FlightPlan has valid GeoJSON (+20)")
        else:
            feedback_parts.append(
                f"✗ FlightPlan geo_json is missing or not valid GeoJSON (got: {str(geo_str)[:80]})"
            )

    # ── Check 3: FlightOperation exists (20 pts) ──────────────────────────────
    if fo and fo.get("name", "").strip().lower() == "kolkata port inspection":
        score += 20
        feedback_parts.append("✓ FlightOperation 'Kolkata Port Inspection' created (+20)")
    elif fo:
        score += 10
        feedback_parts.append(
            f"~ FlightOperation found but name mismatch: '{fo.get('name')}' (+10)"
        )
    else:
        feedback_parts.append("✗ FlightOperation 'Kolkata Port Inspection' not found")

    # ── Check 4: FlightOperation references the NEW plan (25 pts) ────────────
    if fo:
        fo_plan_id = fo.get("flight_plan_id", "")
        fp_new_id = fp.get("id", "") if fp else ""
        if fo_plan_id and fo_plan_id != EXISTING_PLAN_ID and fo_plan_id == fp_new_id:
            score += 25
            feedback_parts.append("✓ FlightOperation uses new 'Kolkata Port Survey' plan (+25)")
        elif fo_plan_id == EXISTING_PLAN_ID:
            feedback_parts.append(
                "✗ FlightOperation still references old 'Flight Plan A' — should use new plan"
            )
        elif fo_plan_id and fo_plan_id != EXISTING_PLAN_ID:
            score += 15
            feedback_parts.append(
                f"~ FlightOperation uses a non-old plan (id={fo_plan_id[:8]}...) (+15)"
            )
        else:
            feedback_parts.append("✗ FlightOperation has no flight_plan set")

    # ── Check 5: FlightOperation drone is F1 #2 (15 pts) ─────────────────────
    if fo:
        drone_id = fo.get("drone_id", "")
        drone_name = fo.get("drone_name", "")
        if drone_id == EXPECTED_DRONE_ID or drone_name == "F1 #2":
            score += 15
            feedback_parts.append("✓ FlightOperation drone is 'F1 #2' (+15)")
        else:
            feedback_parts.append(
                f"✗ FlightOperation drone is '{drone_name}' (expected 'F1 #2')"
            )

    passed = score >= 60
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal score: {score}/100 ({'PASSED' if passed else 'FAILED'}, threshold 60)"

    return {"passed": passed, "score": score, "feedback": feedback}
