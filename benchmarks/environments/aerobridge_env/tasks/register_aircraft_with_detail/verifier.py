#!/usr/bin/env python3
"""Verifier for register_aircraft_with_detail task.

Checks the three-step registration workflow:
  1. Aircraft 'Falcon Eye 3' created with correct attributes
  2. AircraftDetail created and aircraft marked as registered
  3. FlightOperation 'Falcon Eye 3 Maiden Flight' created using the new aircraft

Scoring (100 points total):
  - Aircraft 'Falcon Eye 3' exists:                     20 pts
  - Flight controller ID is 'FE3CTRL334455':            15 pts
  - AircraftDetail exists for Falcon Eye 3:             20 pts
  - AircraftDetail is_registered == True:               15 pts
  - Registration mark == 'IND/UP/2024/003':             10 pts
  - FlightOperation 'Falcon Eye 3 Maiden Flight' exists: 20 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXPECTED_AIRCRAFT_NAME = "Falcon Eye 3"
EXPECTED_FLIGHT_CTRL_ID = "FE3CTRL334455"
EXPECTED_REGISTRATION_MARK = "IND/UP/2024/003"
EXPECTED_OPERATION_NAME = "Falcon Eye 3 Maiden Flight"


def verify_register_aircraft_with_detail(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_path = tmp.name
    tmp.close()
    try:
        copy_from_env("/tmp/register_aircraft_with_detail_result.json", tmp_path)
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
    ac = data.get("aircraft")
    detail = data.get("aircraft_detail")
    fo = data.get("flight_operation")

    # ── Check 1: Aircraft 'Falcon Eye 3' exists (20 pts) ──────────────────────
    if ac and ac.get("name", "").strip() == EXPECTED_AIRCRAFT_NAME:
        score += 20
        feedback_parts.append(f"✓ Aircraft '{EXPECTED_AIRCRAFT_NAME}' created (+20)")
    elif ac:
        score += 10
        feedback_parts.append(f"~ Aircraft found but name: '{ac.get('name')}' (+10)")
    else:
        feedback_parts.append(f"✗ Aircraft '{EXPECTED_AIRCRAFT_NAME}' not found")

    # ── Check 2: Flight controller ID correct (15 pts) ────────────────────────
    if ac:
        flt_ctrl = ac.get("flight_controller_id", "")
        if flt_ctrl and flt_ctrl.strip() == EXPECTED_FLIGHT_CTRL_ID:
            score += 15
            feedback_parts.append(f"✓ Flight controller ID is '{EXPECTED_FLIGHT_CTRL_ID}' (+15)")
        else:
            feedback_parts.append(
                f"✗ Flight controller ID is '{flt_ctrl}', expected '{EXPECTED_FLIGHT_CTRL_ID}'"
            )

    # ── Check 3: AircraftDetail exists for Falcon Eye 3 (20 pts) ─────────────
    if detail and detail.get("aircraft_name", "").strip() == EXPECTED_AIRCRAFT_NAME:
        score += 20
        feedback_parts.append(f"✓ AircraftDetail created for '{EXPECTED_AIRCRAFT_NAME}' (+20)")
    elif detail:
        score += 8
        feedback_parts.append(
            f"~ AircraftDetail found but linked to '{detail.get('aircraft_name')}' (+8)"
        )
    else:
        feedback_parts.append(f"✗ AircraftDetail for '{EXPECTED_AIRCRAFT_NAME}' not found")

    # ── Check 4: is_registered == True (15 pts) ───────────────────────────────
    if detail:
        if detail.get("is_registered") is True:
            score += 15
            feedback_parts.append("✓ AircraftDetail.is_registered is True (+15)")
        else:
            feedback_parts.append(
                f"✗ AircraftDetail.is_registered is {detail.get('is_registered')}, expected True"
            )

    # ── Check 5: Registration mark correct (10 pts) ───────────────────────────
    if detail:
        mark = detail.get("registration_mark", "")
        if mark and mark.strip() == EXPECTED_REGISTRATION_MARK:
            score += 10
            feedback_parts.append(f"✓ Registration mark is '{EXPECTED_REGISTRATION_MARK}' (+10)")
        else:
            feedback_parts.append(
                f"✗ Registration mark is '{mark}', expected '{EXPECTED_REGISTRATION_MARK}'"
            )

    # ── Check 6: FlightOperation 'Falcon Eye 3 Maiden Flight' exists (20 pts) ─
    if fo and fo.get("name", "").strip() == EXPECTED_OPERATION_NAME:
        score += 20
        # Bonus info: check the drone is actually Falcon Eye 3
        drone_name = fo.get("drone_name", "")
        if drone_name == EXPECTED_AIRCRAFT_NAME:
            feedback_parts.append(
                f"✓ FlightOperation '{EXPECTED_OPERATION_NAME}' created using Falcon Eye 3 (+20)"
            )
        else:
            feedback_parts.append(
                f"✓ FlightOperation '{EXPECTED_OPERATION_NAME}' created (+20) "
                f"[note: drone is '{drone_name}', expected '{EXPECTED_AIRCRAFT_NAME}']"
            )
    elif fo:
        score += 10
        feedback_parts.append(
            f"~ FlightOperation found but name: '{fo.get('name')}' (+10)"
        )
    else:
        feedback_parts.append(f"✗ FlightOperation '{EXPECTED_OPERATION_NAME}' not found")

    passed = score >= 60
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal score: {score}/100 ({'PASSED' if passed else 'FAILED'}, threshold 60)"

    return {"passed": passed, "score": score, "feedback": feedback}
