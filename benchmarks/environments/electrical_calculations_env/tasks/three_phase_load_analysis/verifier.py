#!/usr/bin/env python3
"""
Verifier for Three-Phase Load Analysis task.

The agent must use the 3-phase power calculators to compute:
  - Apparent power: S = √3 × V × I = 1.732 × 400 × 24 = 16,627 VA
  - Real power:     P = √3 × V × I × PF = 16,627 × 0.80 = 13,302 W
  - Reactive power: Q = √3 × V × I × sin(arccos(PF)) = 16,627 × 0.60 = 9,976 VAR

Scoring (100 points total):
  - Reactive power result on screen (≈9,976 VAR ±3%):   35 pts [key criterion]
  - Real power result visible (≈13,302 W ±3%):          20 pts
  - Apparent power result visible (≈16,627 VA ±3%):     20 pts
  - Final screen is a three-phase power calculator:      15 pts
  - Any three-phase calculation visible in final dump:   10 pts

Pass threshold: 60 points (must include reactive power result)
"""

import xml.etree.ElementTree as ET
import re
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# Expected results
EXPECTED_APPARENT_VA = 16627.2
EXPECTED_REAL_W      = 13301.8
EXPECTED_REACTIVE_VAR = 9976.3
TOLERANCE_PCT = 3.0


def _parse_ui_dump(xml_content):
    """Extract all text values and numeric tokens from Android UI dump XML."""
    texts = []
    numbers = set()
    try:
        root = ET.fromstring(xml_content)
        for node in root.iter():
            text = node.get('text', '').strip()
            if text:
                texts.append(text.lower())
                # Extract all numeric values from the text
                for m in re.finditer(r'\d+\.?\d*', text):
                    try:
                        numbers.add(float(m.group()))
                    except ValueError:
                        pass
            # Also check content-desc
            cd = node.get('content-desc', '').strip()
            if cd:
                texts.append(cd.lower())
    except Exception as e:
        logger.warning(f"UI dump parse error: {e}")
    return texts, numbers


def _number_near(numbers, target, tol_pct=3.0):
    """Return True if any number in the set is within tol_pct% of target."""
    target = float(target)
    if target == 0:
        return False
    margin = abs(target) * tol_pct / 100.0
    for num in numbers:
        if abs(num - target) <= margin:
            return True
    return False


def _has_threephase_keywords(texts):
    """Check if the final screen shows three-phase power calculator content."""
    threephase_terms = [
        'three', '3 phase', '3phase', 'three-phase', 'three phase',
        '3-phase', 'apparent', 'reactive', 'real power',
    ]
    combined = ' '.join(texts)
    return any(term in combined for term in threephase_terms)


def verify_three_phase_load_analysis(traj, env_info, task_info):
    """
    Verify that the agent correctly computed all three power components
    for the 3-phase, 400V, 24A, PF=0.80 feeder.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # --- Copy UI dump from Android device ---
    xml_content = ""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        # Try task-specific dump first, fall back to generic
        for src in ('/sdcard/ui_dump_three_phase_load.xml', '/sdcard/ui_dump.xml'):
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

    # --- Criterion 1 (35 pts): Reactive power result visible on final screen ---
    # Q = 9,976 VAR
    reactive_found = _number_near(numbers, EXPECTED_REACTIVE_VAR, TOLERANCE_PCT)
    if reactive_found:
        score += 35
        feedback_parts.append(f"Reactive power (~{EXPECTED_REACTIVE_VAR:.0f} VAR) visible on screen")
    else:
        feedback_parts.append(f"Reactive power ({EXPECTED_REACTIVE_VAR:.0f} VAR) NOT found on screen")

    # --- Criterion 2 (20 pts): Real power result visible ---
    # P = 13,302 W
    real_found = _number_near(numbers, EXPECTED_REAL_W, TOLERANCE_PCT)
    if real_found:
        score += 20
        feedback_parts.append(f"Real power (~{EXPECTED_REAL_W:.0f} W) visible on screen")
    else:
        feedback_parts.append(f"Real power ({EXPECTED_REAL_W:.0f} W) NOT found on screen")

    # --- Criterion 3 (20 pts): Apparent power result visible ---
    # S = 16,627 VA
    apparent_found = _number_near(numbers, EXPECTED_APPARENT_VA, TOLERANCE_PCT)
    if apparent_found:
        score += 20
        feedback_parts.append(f"Apparent power (~{EXPECTED_APPARENT_VA:.0f} VA) visible on screen")
    else:
        feedback_parts.append(f"Apparent power ({EXPECTED_APPARENT_VA:.0f} VA) NOT found on screen")

    # --- Criterion 4 (15 pts): Three-phase calculator visible with a result ---
    # Gate on at least one numeric result to avoid matching app main-menu navigation items
    # (which also contain words like 'three', 'apparent', 'reactive', 'real power')
    any_result = reactive_found or real_found or apparent_found
    if _has_threephase_keywords(texts) and any_result:
        score += 15
        feedback_parts.append("Three-phase power calculator is visible")
    else:
        feedback_parts.append("No three-phase calculator keywords found on final screen")

    # --- Criterion 5 (10 pts): Task-relevant inputs visible (400V, 24A) ---
    has_voltage = _number_near(numbers, 400, 1.0)
    has_current = _number_near(numbers, 24, 1.0)
    if has_voltage or has_current:
        score += 10
        feedback_parts.append("Task input values (400V / 24A) visible on screen")
    else:
        feedback_parts.append("Task input values not found on final screen")

    # Pass requires at least the reactive power result
    passed = score >= 60 and reactive_found

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
