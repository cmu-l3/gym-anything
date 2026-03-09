#!/usr/bin/env python3
"""
Verifier for Three-Phase Line-to-Phase Conversions task.

Supply: 415 V line, 63 A line current.

Required conversions:
  - Wye phase voltage:   V_ph = V_L / √3 = 415 / 1.732 = 239.6 V
  - Delta phase current: I_ph = I_L / √3 = 63  / 1.732 = 36.37 A

Scoring (100 points total):
  - Delta phase current (≈36.37 A ±3%):                  35 pts [MANDATORY for pass]
  - Wye phase voltage (≈239.6 V ±3%):                    30 pts
  - Line/phase conversion keywords visible:               20 pts
  - Input values (415V / 63A) visible:                    15 pts

Pass threshold: 60 points (delta phase current required)
"""

import xml.etree.ElementTree as ET
import re
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXPECTED_PHASE_VOLTAGE_V  = 239.6   # V_line / √3 = 415 / 1.732
EXPECTED_PHASE_CURRENT_A  = 36.37   # I_line / √3 = 63  / 1.732
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


def _has_conversion_keywords(texts):
    # Use compound phrases only — single words like 'line', 'phase', 'conversion'
    # appear on the app's main menu and would trigger false positives on the
    # do-nothing baseline. Compound phrases are specific to the calculator screen.
    keywords = [
        'line to phase', 'phase to line',
        'line current', 'phase current',
        'line voltage', 'phase voltage',
        'l-p', 'l to p',
    ]
    combined = ' '.join(texts)
    return any(kw in combined for kw in keywords)


def verify_three_phase_line_phase_conversions(traj, env_info, task_info):
    """
    Verify that the agent computed both the wye phase voltage and
    the delta phase current for the 415V, 63A supply.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    xml_content = ""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        for src in ('/sdcard/ui_dump_lp_conv.xml', '/sdcard/ui_dump.xml'):
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

    # Criterion 1 (35 pts): Delta phase current ≈ 36.37 A
    current_found = _number_near(numbers, EXPECTED_PHASE_CURRENT_A, TOLERANCE_PCT)
    if current_found:
        score += 35
        feedback_parts.append(f"Delta phase current (~{EXPECTED_PHASE_CURRENT_A:.2f} A) visible")
    else:
        feedback_parts.append(f"Delta phase current ({EXPECTED_PHASE_CURRENT_A:.2f} A) NOT found")

    # Criterion 2 (30 pts): Wye phase voltage ≈ 239.6 V
    voltage_found = _number_near(numbers, EXPECTED_PHASE_VOLTAGE_V, TOLERANCE_PCT)
    if voltage_found:
        score += 30
        feedback_parts.append(f"Wye phase voltage (~{EXPECTED_PHASE_VOLTAGE_V:.1f} V) visible")
    else:
        feedback_parts.append(f"Wye phase voltage ({EXPECTED_PHASE_VOLTAGE_V:.1f} V) NOT found")

    # Criterion 3 (20 pts): Conversion calculator visible with a result
    # Gate on at least one numeric result to avoid matching app main-menu navigation
    # items (e.g. "Line Current / Phase Current Converter" menu entry).
    any_result = current_found or voltage_found
    if _has_conversion_keywords(texts) and any_result:
        score += 20
        feedback_parts.append("Line/phase conversion calculator is visible")
    else:
        feedback_parts.append("No line/phase conversion keywords on final screen")

    # Criterion 4 (15 pts): Input values (415V / 63A) visible
    has_415 = _number_near(numbers, 415, 1.0)
    has_63  = _number_near(numbers, 63,  1.0)
    if has_415 or has_63:
        score += 15
        feedback_parts.append("Input values (415V / 63A) visible")
    else:
        feedback_parts.append("Input values (415V / 63A) not found on final screen")

    passed = score >= 60 and current_found

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
