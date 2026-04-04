#!/usr/bin/env python3
"""
Verifier for Single-Phase Power Quality Audit task.

The agent must use the single-phase power calculators to compute:
  - Apparent power: S = V × I = 230 × 28 = 6,440 VA
  - Real power:     P = V × I × PF = 6,440 × 0.65 = 4,186 W
  - Reactive power: Q = V × I × sin(arccos(0.65)) = 6,440 × 0.7599 = 4,894 VAR

Scoring (100 points total):
  - Reactive power result on screen (≈4,894 VAR ±3%):   35 pts [key criterion]
  - Real power result visible (≈4,186 W ±3%):           20 pts
  - Apparent power result visible (≈6,440 VA ±3%):      20 pts
  - Single-phase power calculator keywords visible:      15 pts
  - Task input values (230V / 28A) visible:              10 pts

Pass threshold: 60 points (reactive power result required)
"""

import xml.etree.ElementTree as ET
import re
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXPECTED_APPARENT_VA  = 6440.0
EXPECTED_REAL_W       = 4186.0
EXPECTED_REACTIVE_VAR = 4894.0
TOLERANCE_PCT = 3.0


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


def _has_singlephase_keywords(texts):
    terms = ['single', '1 phase', '1phase', 'single-phase', 'single phase',
             'apparent', 'reactive', 'real power', 'power factor']
    combined = ' '.join(texts)
    return any(term in combined for term in terms)


def verify_single_phase_power_quality_audit(traj, env_info, task_info):
    """
    Verify that the agent computed all single-phase power components
    for the 230V, 28A, PF=0.65 circuit.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    xml_content = ""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        for src in ('/sdcard/ui_dump_sp_power.xml', '/sdcard/ui_dump.xml'):
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

    # Criterion 1 (35 pts): Reactive power result ≈ 4,894 VAR
    reactive_found = _number_near(numbers, EXPECTED_REACTIVE_VAR, TOLERANCE_PCT)
    if reactive_found:
        score += 35
        feedback_parts.append(f"Reactive power (~{EXPECTED_REACTIVE_VAR:.0f} VAR) visible")
    else:
        feedback_parts.append(f"Reactive power ({EXPECTED_REACTIVE_VAR:.0f} VAR) NOT found")

    # Criterion 2 (20 pts): Real power ≈ 4,186 W
    real_found = _number_near(numbers, EXPECTED_REAL_W, TOLERANCE_PCT)
    if real_found:
        score += 20
        feedback_parts.append(f"Real power (~{EXPECTED_REAL_W:.0f} W) visible")
    else:
        feedback_parts.append(f"Real power ({EXPECTED_REAL_W:.0f} W) NOT found")

    # Criterion 3 (20 pts): Apparent power ≈ 6,440 VA
    apparent_found = _number_near(numbers, EXPECTED_APPARENT_VA, TOLERANCE_PCT)
    if apparent_found:
        score += 20
        feedback_parts.append(f"Apparent power (~{EXPECTED_APPARENT_VA:.0f} VA) visible")
    else:
        feedback_parts.append(f"Apparent power ({EXPECTED_APPARENT_VA:.0f} VA) NOT found")

    # Criterion 4 (15 pts): Single-phase calculator visible with a result
    # Gate on at least one numeric result to avoid matching app main-menu navigation items
    # (which also contain words like 'single', 'apparent', 'reactive', 'power factor')
    any_result = reactive_found or real_found or apparent_found
    if _has_singlephase_keywords(texts) and any_result:
        score += 15
        feedback_parts.append("Single-phase power calculator is visible")
    else:
        feedback_parts.append("No single-phase calculator keywords on final screen")

    # Criterion 5 (10 pts): Input values visible (230V / 28A)
    has_voltage = _number_near(numbers, 230, 1.0)
    has_current = _number_near(numbers, 28, 1.0)
    if has_voltage or has_current:
        score += 10
        feedback_parts.append("Task input values (230V / 28A) visible")
    else:
        feedback_parts.append("Task input values not found on final screen")

    passed = score >= 60 and reactive_found

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
