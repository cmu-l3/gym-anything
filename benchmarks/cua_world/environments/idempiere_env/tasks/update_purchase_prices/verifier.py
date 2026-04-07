#!/usr/bin/env python3
"""Verifier for update_purchase_prices task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_update_purchase_prices(traj, env_info, task_info):
    """
    Verify that three product prices were updated on the Purchase 2003 price list.

    Scoring (100 points):
    - Mulch 10# price updated to $3.15 (±$0.05): 33 points
    - Fertilizer #50 price updated to $19.50 (±$0.05): 33 points
    - Grass Seed Container price updated to $52.00 (±$0.10): 34 points

    Pass threshold: 70 points (at least 2 of 3 prices correct)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/update_purchase_prices_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []

        def price_ok(current_str, expected, tolerance=0.05):
            try:
                return abs(float(current_str) - expected) <= tolerance
            except (ValueError, TypeError):
                return False

        def price_changed(current_str, initial_str):
            try:
                return abs(float(current_str) - float(initial_str)) > 0.001
            except (ValueError, TypeError):
                return False

        # Criterion 1: Mulch 10# updated to $3.15
        mulch = result.get('current_mulch_price', '0')
        init_mulch = result.get('initial_mulch_price', '0')
        if price_ok(mulch, 3.15) and price_changed(mulch, init_mulch):
            score += 33
            feedback_parts.append(f"Mulch 10# price updated correctly: ${mulch}")
        else:
            feedback_parts.append(
                f"Mulch 10# incorrect: got ${mulch}, expected $3.15 (baseline: ${init_mulch})"
            )

        # Criterion 2: Fertilizer #50 updated to $19.50
        fert = result.get('current_fert_price', '0')
        init_fert = result.get('initial_fert_price', '0')
        if price_ok(fert, 19.50) and price_changed(fert, init_fert):
            score += 33
            feedback_parts.append(f"Fertilizer #50 price updated correctly: ${fert}")
        else:
            feedback_parts.append(
                f"Fertilizer #50 incorrect: got ${fert}, expected $19.50 (baseline: ${init_fert})"
            )

        # Criterion 3: Grass Seed Container updated to $52.00
        grass = result.get('current_grass_price', '0')
        init_grass = result.get('initial_grass_price', '0')
        if price_ok(grass, 52.00, tolerance=0.10) and price_changed(grass, init_grass):
            score += 34
            feedback_parts.append(f"Grass Seed Container price updated correctly: ${grass}")
        else:
            feedback_parts.append(
                f"Grass Seed Container incorrect: got ${grass}, expected $52.00 (baseline: ${init_grass})"
            )

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        logger.exception("Verifier error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
