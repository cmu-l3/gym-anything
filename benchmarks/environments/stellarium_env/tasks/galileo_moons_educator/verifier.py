#!/usr/bin/env python3
"""Verifier for galileo_moons_educator task.

A science educator prepares a Galileo's moons demonstration using Stellarium,
set to Florence Italy (43.7696°N, 11.2558°E) at the January 1610 dates when
Galileo first observed Jupiter's four moons.
"""

import json
import math
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_galileo_moons_educator(traj, env_info, task_info):
    """
    Verify the galileo_moons_educator task.

    Scoring (100 points total):
    - Location set to Florence Italy (lat ≈ 0.7640 rad, ±0.08):  25 points
    - Constellation lines enabled (flag_constellation_drawing=true): 15 points
    - Atmosphere disabled (flag_atmosphere=false):                  15 points
    - At least 2 new screenshots taken:                            25 points
    - Demo notes created with historical content:                  20 points

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get("metadata", {})
    target_lat_rad = metadata.get("target_lat_rad", 0.76397)   # Florence 43.7696°N
    target_lon_rad = metadata.get("target_lon_rad", 0.19648)   # Florence 11.2558°E

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/galileo_moons_educator_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except OSError:
                pass

        score = 0
        feedback_parts = []

        # ── 1. Location: Florence Italy (25 pts) ──────────────────────────────
        lat_rad = result.get("lat_rad")
        if lat_rad is not None:
            lat_diff = abs(lat_rad - target_lat_rad)
            if lat_diff <= 0.08:          # ≈ 4.6° tolerance
                score += 25
                feedback_parts.append("Location set to Florence Italy")
            else:
                lat_deg = math.degrees(lat_rad)
                expected_deg = math.degrees(target_lat_rad)
                feedback_parts.append(
                    f"Location incorrect: got {lat_deg:.2f}° lat, "
                    f"expected {expected_deg:.2f}°"
                )
        else:
            feedback_parts.append("Location data unavailable")

        # ── 2. Constellation lines enabled (15 pts) ───────────────────────────
        if result.get("flag_constellation_drawing") is True:
            score += 15
            feedback_parts.append("Constellation lines enabled")
        else:
            feedback_parts.append("Constellation lines not enabled")

        # ── 3. Atmosphere disabled for dark sky view (15 pts) ─────────────────
        if result.get("flag_atmosphere") is False:
            score += 15
            feedback_parts.append("Atmosphere disabled")
        else:
            feedback_parts.append("Atmosphere still on (should be disabled for clarity)")

        # ── 4. Screenshots taken during demonstration (25 pts) ────────────────
        new_ss_count = result.get("new_screenshot_count", 0)
        if new_ss_count >= 2:
            score += 25
            feedback_parts.append(f"Demonstration screenshots captured ({new_ss_count} new)")
        elif new_ss_count == 1:
            score += 10
            feedback_parts.append("Only 1 screenshot found; need at least 2 for both nights")
        else:
            feedback_parts.append("No demonstration screenshots taken")

        # ── 5. Demo notes with historical educational content (20 pts) ────────
        notes_exists = result.get("demo_notes_exists", False)
        notes_has_1610 = result.get("demo_notes_has_1610", False)
        notes_has_galileo = result.get("demo_notes_has_galileo", False)
        notes_has_jupiter = result.get("demo_notes_has_jupiter", False)
        notes_has_moons = result.get("demo_notes_has_moons", False)

        if notes_exists:
            keyword_count = sum([
                notes_has_1610,
                notes_has_galileo,
                notes_has_jupiter,
                notes_has_moons,
            ])
            if keyword_count >= 3:
                score += 20
                feedback_parts.append(
                    "Demo notes contain thorough historical content "
                    "(1610, Galileo, Jupiter, moons)"
                )
            elif keyword_count == 2:
                score += 10
                feedback_parts.append(
                    f"Demo notes present but sparse "
                    f"({keyword_count}/4 historical keywords)"
                )
            else:
                score += 5
                feedback_parts.append(
                    "Demo notes file created but lacks key historical content"
                )
        else:
            feedback_parts.append(
                "No demo notes found at /home/ga/Desktop/galileo_demo_notes.txt"
            )

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result JSON malformed: {e}",
        }
    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verifier error: {e}",
        }
