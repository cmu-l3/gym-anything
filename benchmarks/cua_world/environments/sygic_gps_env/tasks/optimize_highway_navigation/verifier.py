#!/usr/bin/env python3
"""Verifier for optimize_highway_navigation task.

Scoring (100 points total, 8 criteria):
- Criterion 1: Avoid highways disabled (false)                  — 13 pts
- Criterion 2: Avoid toll roads disabled (false)                — 13 pts
- Criterion 3: Avoid unpaved roads still enabled (true)         — 12 pts
- Criterion 4: Route compute set to Fastest ("1")               — 13 pts
- Criterion 5: Compass enabled (true)                           — 12 pts
- Criterion 6: Driving mode set to 2D ("0")                     — 13 pts
- Criterion 7: 3D terrain disabled (false)                      — 12 pts
- Criterion 8: Font size set to Bigger ("1")                    — 12 pts

Pass threshold: 70 points

Gate: If BOTH route_compute AND driving_mode are unchanged from their
setup baseline values (route_compute="0" and driving_mode="1"), the agent
did no meaningful work => score forced to 0.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_optimize_highway_navigation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(
                "/data/local/tmp/optimize_highway_navigation_result.json",
                temp_file.name
            )
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []

        # --- GATE CHECK ---
        # If both route_compute and driving_mode are unchanged from setup
        # values, the agent made no meaningful progress.
        baseline_rc = result.get('baseline_route_compute', '0').strip()
        baseline_dm = result.get('baseline_driving_mode', '1').strip()
        current_rc = result.get('route_compute', '').strip()
        current_dm = result.get('driving_mode', '').strip()

        if current_rc == baseline_rc and current_dm == baseline_dm:
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    "Gate failed: route_compute and driving_mode are both "
                    "unchanged from setup values "
                    f"(route_compute='{current_rc}', driving_mode='{current_dm}'). "
                    "No meaningful settings changes detected."
                )
            }

        # --- Criterion 1: Avoid highways = false (13 pts) ---
        try:
            avoid_hw = result.get('avoid_highways', '').strip().lower()
            if avoid_hw == 'false':
                score += 13
                feedback_parts.append("Avoid highways disabled (correct)")
            else:
                feedback_parts.append(
                    f"Avoid highways is '{avoid_hw}', expected 'false'"
                )
        except Exception as e:
            feedback_parts.append(f"Avoid highways check error: {e}")

        # --- Criterion 2: Avoid toll roads = false (13 pts) ---
        try:
            avoid_tolls = result.get('avoid_toll_roads', '').strip().lower()
            if avoid_tolls == 'false':
                score += 13
                feedback_parts.append("Avoid toll roads disabled (correct)")
            else:
                feedback_parts.append(
                    f"Avoid toll roads is '{avoid_tolls}', expected 'false'"
                )
        except Exception as e:
            feedback_parts.append(f"Avoid toll roads check error: {e}")

        # --- Criterion 3: Avoid unpaved roads = true (12 pts) ---
        try:
            avoid_unpaved = result.get('avoid_unpaved_roads', '').strip().lower()
            if avoid_unpaved == 'true':
                score += 12
                feedback_parts.append("Avoid unpaved roads still enabled (correct)")
            else:
                feedback_parts.append(
                    f"Avoid unpaved roads is '{avoid_unpaved}', expected 'true'"
                )
        except Exception as e:
            feedback_parts.append(f"Avoid unpaved roads check error: {e}")

        # --- Criterion 4: Route compute = "1" (Fastest) (13 pts) ---
        try:
            route_compute = result.get('route_compute', '').strip()
            if route_compute == '1':
                score += 13
                feedback_parts.append("Route compute set to Fastest (correct)")
            else:
                feedback_parts.append(
                    f"Route compute is '{route_compute}', expected '1' (Fastest)"
                )
        except Exception as e:
            feedback_parts.append(f"Route compute check error: {e}")

        # --- Criterion 5: Compass enabled = true (12 pts) ---
        try:
            compass = result.get('compass_always_on', '').strip().lower()
            if compass == 'true':
                score += 12
                feedback_parts.append("Compass enabled (correct)")
            else:
                feedback_parts.append(
                    f"Compass is '{compass}', expected 'true'"
                )
        except Exception as e:
            feedback_parts.append(f"Compass check error: {e}")

        # --- Criterion 6: Driving mode = "0" (2D) (13 pts) ---
        try:
            driving_mode = result.get('driving_mode', '').strip()
            if driving_mode == '0':
                score += 13
                feedback_parts.append("Driving mode set to 2D (correct)")
            else:
                feedback_parts.append(
                    f"Driving mode is '{driving_mode}', expected '0' (2D)"
                )
        except Exception as e:
            feedback_parts.append(f"Driving mode check error: {e}")

        # --- Criterion 7: 3D terrain = false (12 pts) ---
        try:
            terrain = result.get('terrain_3d', '').strip().lower()
            if terrain == 'false':
                score += 12
                feedback_parts.append("3D terrain disabled (correct)")
            elif terrain in ('', 'unknown'):
                # Key might not exist in prefs XML if never toggled;
                # treat missing as "not disabled" but give partial credit
                # if the key simply doesn't exist in this app version.
                feedback_parts.append(
                    "3D terrain preference not found in XML "
                    "(key may not exist in this app version)"
                )
            else:
                feedback_parts.append(
                    f"3D terrain is '{terrain}', expected 'false'"
                )
        except Exception as e:
            feedback_parts.append(f"3D terrain check error: {e}")

        # --- Criterion 8: Font size = "1" (Bigger) (12 pts) ---
        try:
            font_size = result.get('font_size', '').strip()
            if font_size == '1':
                score += 12
                feedback_parts.append("Font size set to Bigger (correct)")
            elif font_size in ('', 'unknown'):
                feedback_parts.append(
                    "Font size preference not found in XML"
                )
            else:
                feedback_parts.append(
                    f"Font size is '{font_size}', expected '1' (Bigger)"
                )
        except Exception as e:
            feedback_parts.append(f"Font size check error: {e}")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria evaluated"
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file /data/local/tmp/optimize_highway_navigation_result.json not found"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file JSON parse error: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verifier error: {str(e)}"
        }
