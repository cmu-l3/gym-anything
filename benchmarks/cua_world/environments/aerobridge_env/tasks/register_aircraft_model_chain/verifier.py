#!/usr/bin/env python3
"""Verifier for register_aircraft_model_chain task.

Checks the three-step chain:
  1. AircraftModel 'Nile Scout 200' created with ROTORCRAFT category
  2. AircraftAssembly created for Nile Scout 200
  3. Aircraft 'NS-001' created using the new assembly

Scoring (100 points total):
  - AircraftModel 'Nile Scout 200' exists:           20 pts
  - Model category is ROTORCRAFT (2):                15 pts
  - AircraftAssembly exists for Nile Scout 200:      25 pts
  - Aircraft 'NS-001' exists:                        20 pts
  - Aircraft uses the new Nile Scout 200 assembly:   20 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

ROTORCRAFT_CATEGORY = 2  # from AircraftModel.category choices


def verify_register_aircraft_model_chain(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_path = tmp.name
    tmp.close()
    try:
        copy_from_env("/tmp/register_aircraft_model_chain_result.json", tmp_path)
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
    am = data.get("aircraft_model")
    aa = data.get("aircraft_assembly")
    ac = data.get("aircraft")

    # ── Check 1: AircraftModel exists (20 pts) ────────────────────────────────
    if am and am.get("name", "").strip().lower() == "nile scout 200":
        score += 20
        feedback_parts.append("✓ AircraftModel 'Nile Scout 200' created (+20)")
    elif am:
        score += 10
        feedback_parts.append(f"~ AircraftModel found but name: '{am.get('name')}' (+10)")
    else:
        feedback_parts.append("✗ AircraftModel 'Nile Scout 200' not found")

    # ── Check 2: Model category is ROTORCRAFT (15 pts) ────────────────────────
    if am:
        cat = am.get("category")
        if cat == ROTORCRAFT_CATEGORY:
            score += 15
            feedback_parts.append("✓ AircraftModel category is ROTORCRAFT (2) (+15)")
        else:
            cat_names = {0: "Other", 1: "FIXED WING", 2: "ROTORCRAFT", 3: "LIGHTER-THAN-AIR",
                         4: "HYBRID LIFT", 5: "MICRO", 6: "SMALL", 7: "MEDIUM", 8: "Large"}
            feedback_parts.append(
                f"✗ AircraftModel category is '{cat_names.get(cat, cat)}' ({cat}), expected ROTORCRAFT (2)"
            )

    # ── Check 3: AircraftAssembly exists for Nile Scout 200 (25 pts) ─────────
    if aa and aa.get("model_name", "").strip().lower() == "nile scout 200":
        score += 25
        feedback_parts.append("✓ AircraftAssembly created for Nile Scout 200 (+25)")
    elif aa:
        score += 10
        feedback_parts.append(
            f"~ AircraftAssembly found but for model '{aa.get('model_name')}' (+10)"
        )
    else:
        feedback_parts.append("✗ AircraftAssembly for Nile Scout 200 not found")

    # ── Check 4: Aircraft 'NS-001' exists (20 pts) ────────────────────────────
    if ac and ac.get("name", "").strip().upper() == "NS-001":
        score += 20
        feedback_parts.append("✓ Aircraft 'NS-001' created (+20)")
    elif ac:
        score += 10
        feedback_parts.append(f"~ Aircraft found but name: '{ac.get('name')}' (+10)")
    else:
        feedback_parts.append("✗ Aircraft 'NS-001' not found")

    # ── Check 5: Aircraft uses Nile Scout 200 assembly (20 pts) ──────────────
    if ac:
        asm_model = ac.get("assembly_model_name", "")
        if asm_model and asm_model.strip().lower() == "nile scout 200":
            score += 20
            feedback_parts.append("✓ Aircraft 'NS-001' uses Nile Scout 200 assembly (+20)")
        elif asm_model:
            feedback_parts.append(
                f"✗ Aircraft uses assembly for model '{asm_model}', expected 'Nile Scout 200'"
            )
        else:
            feedback_parts.append("✗ Aircraft has no final_assembly set (or assembly has no model)")

    passed = score >= 60
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal score: {score}/100 ({'PASSED' if passed else 'FAILED'}, threshold 60)"

    return {"passed": passed, "score": score, "feedback": feedback}
