#!/usr/bin/env python3
"""
Verifier for Motor Cable Sizing Calculation task.

The agent must chain two calculations:
  Step 1. Motor input power: P_in = 3700 / 0.88 = 4204.5 W
  Step 2. Motor line current: I = P_in / (V × PF) = 4204.5 / (240 × 0.85) = 20.61 A
  Step 3. Cable size calculator: V=240, I=20.61, L=35m, PF=0.85, VD=5%

The key verifiable result is the motor current (~20.61 A), which can only be
obtained by correctly applying BOTH efficiency and power factor. Any value
that is correct only for output power (I = 3700/(240×0.85) = 18.14A) or
that ignores power factor (I = 4204.5/240 = 17.52A) will fail this criterion.

Scoring (100 points total):
  - Motor current on screen (20.61 A ±3%):             40 pts [MANDATORY for pass]
  - Cable size calculator keywords visible:              20 pts
  - A cable size result is visible:                      20 pts
  - Cable sizing parameters (240V / 35m) visible:        10 pts
  - PF=0.85 visible (power factor entered correctly):    10 pts

Pass threshold: 60 points (motor current result required)
"""

import xml.etree.ElementTree as ET
import re
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXPECTED_CURRENT_A  = 20.61
TOLERANCE_PCT       = 3.0

# Wrong answers to watch for (if these appear but not the correct answer,
# it suggests the agent made a partial error)
WRONG_CURRENT_NO_EFF   = 18.14  # ignoring efficiency: 3700/(240*0.85)
WRONG_CURRENT_NO_PF    = 17.52  # ignoring PF: 4204.5/240


def _parse_ui_dump(xml_content):
    texts = []
    numbers = set()
    try:
        root = ET.fromstring(xml_content)
        for node in root.iter():
            text = node.get('text', '').strip()
            if text:
                texts.append(text.lower())
                for m in re.finditer(r'\d+\.?\d*', text):
                    try:
                        numbers.add(float(m.group()))
                    except ValueError:
                        pass
            cd = node.get('content-desc', '').strip()
            if cd:
                texts.append(cd.lower())
    except Exception as e:
        logger.warning(f"UI dump parse error: {e}")
    return texts, numbers


def _number_near(numbers, target, tol_pct=3.0):
    target = float(target)
    if target == 0:
        return False
    margin = abs(target) * tol_pct / 100.0
    for num in numbers:
        if abs(num - target) <= margin:
            return True
    return False


def _has_cable_keywords(texts):
    cable_terms = ['cable', 'size', 'mm', 'awg', 'conductor', 'wire', 'voltage drop']
    combined = ' '.join(texts)
    return any(term in combined for term in cable_terms)


def _has_cable_size_result(texts, numbers):
    """
    Check if a cable size result is visible on screen.
    Only match on explicit unit text ('mm²', 'mm2', 'awg') to avoid
    false positives from bare calculator button digits (e.g. button '4'
    being mistaken for 4.0 mm²).
    """
    combined = ' '.join(texts)
    return 'mm²' in combined or 'mm2' in combined or 'awg' in combined


def verify_motor_cable_sizing_calculation(traj, env_info, task_info):
    """
    Verify that the agent correctly computed the motor current (accounting for
    both efficiency and power factor) and then used it in the cable size calculator.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    xml_content = ""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        for src in ('/sdcard/ui_dump_motor_cable.xml', '/sdcard/ui_dump.xml'):
            try:
                copy_from_env(src, tmp.name)
                with open(tmp.name, 'r', encoding='utf-8', errors='replace') as f:
                    xml_content = f.read()
                if xml_content.strip():
                    break
            except Exception:
                pass
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    if not xml_content.strip():
        return {
            "passed": False,
            "score": 0,
            "feedback": "No UI dump available — export script may have failed"
        }

    texts, numbers = _parse_ui_dump(xml_content)

    score = 0
    feedback_parts = []

    # Criterion 1 (40 pts): Motor current ≈ 20.61 A
    # This requires both efficiency (4204.5 W input) AND power factor applied
    current_correct = _number_near(numbers, EXPECTED_CURRENT_A, TOLERANCE_PCT)
    if current_correct:
        score += 40
        feedback_parts.append(f"Correct motor current (~{EXPECTED_CURRENT_A:.2f} A) visible")
    else:
        # Check if they got a wrong answer from a partial calculation
        if _number_near(numbers, WRONG_CURRENT_NO_EFF, TOLERANCE_PCT):
            feedback_parts.append(
                f"Wrong current ({WRONG_CURRENT_NO_EFF:.2f} A) — efficiency not applied"
            )
        elif _number_near(numbers, WRONG_CURRENT_NO_PF, TOLERANCE_PCT):
            feedback_parts.append(
                f"Wrong current ({WRONG_CURRENT_NO_PF:.2f} A) — power factor not applied"
            )
        else:
            feedback_parts.append(f"Correct current ({EXPECTED_CURRENT_A:.2f} A) NOT found")

    # Criterion 2 (20 pts): Cable size calculator keywords visible
    if _has_cable_keywords(texts):
        score += 20
        feedback_parts.append("Cable size calculator is visible")
    else:
        feedback_parts.append("Cable size calculator NOT visible on final screen")

    # Criterion 3 (20 pts): A cable size result shown
    if _has_cable_size_result(texts, numbers):
        score += 20
        feedback_parts.append("Cable size result visible on screen")
    else:
        feedback_parts.append("No cable size result found on screen")

    # Criterion 4 (10 pts): Cable parameters (240V, 35m) visible
    has_voltage = _number_near(numbers, 240, 1.0)
    has_length  = _number_near(numbers, 35, 1.0)
    if has_voltage or has_length:
        score += 10
        feedback_parts.append("Cable sizing parameters (240V / 35m) visible")
    else:
        feedback_parts.append("Cable sizing parameters not found on final screen")

    # Criterion 5 (10 pts): Power factor (0.85) visible
    has_pf = _number_near(numbers, 0.85, 5.0)
    if has_pf:
        score += 10
        feedback_parts.append("Power factor (0.85) visible on screen")
    else:
        feedback_parts.append("Power factor not visible on final screen")

    passed = score >= 60 and current_correct

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
