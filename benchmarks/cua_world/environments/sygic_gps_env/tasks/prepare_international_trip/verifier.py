#!/usr/bin/env python3
"""Verifier for prepare_international_trip task.

Scoring (100 points, 20 per criterion):
  Criterion 1: Distance units changed to Miles          (value "0")  — 20 pts
  Criterion 2: Temperature units changed to Fahrenheit   (value "Imperial") — 20 pts
  Criterion 3: GPS coordinate format changed to DMS      (value "1")  — 20 pts
  Criterion 4: Time format changed to 12h                (value "1")  — 20 pts
  Criterion 5: Color scheme changed to Night mode        (value "2")  — 20 pts

Pass threshold: 70 points (at least 4 of 5, or 3 of 5 with partial credit).

Gate: If BOTH distance_units AND temperature_units are still at their
setup defaults (unchanged), the agent did no meaningful work => score 0.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_prepare_international_trip(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(
                "/data/local/tmp/prepare_international_trip_result.json", temp_file.name
            )
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []

        # --- GATE CHECK ---
        # If both distance_units and temperature_units are unchanged from
        # their setup baselines, the agent did no work at all.
        baseline_distance = result.get('baseline_distance_units', '1')
        baseline_temp = result.get('baseline_temperature_units', 'Metric')
        current_distance = result.get('distance_units', '')
        current_temp = result.get('temperature_units', '')

        distance_unchanged = (current_distance == baseline_distance)
        temp_unchanged = (current_temp == baseline_temp)

        if distance_unchanged and temp_unchanged:
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    "Gate failed: both distance_units and temperature_units "
                    "are still at their setup defaults — no work was done."
                )
            }

        # --- Criterion 1: Distance units => "0" (Miles) — 20 pts ---
        expected_distance = metadata.get('expected_distance_units', '0')
        try:
            if current_distance == expected_distance:
                score += 20
                feedback_parts.append("Distance units changed to Miles")
            else:
                feedback_parts.append(
                    f"Distance units is '{current_distance}', "
                    f"expected '{expected_distance}' (Miles)"
                )
        except Exception as e:
            feedback_parts.append(f"Distance units check error: {e}")

        # --- Criterion 2: Temperature units => "Imperial" (Fahrenheit) — 20 pts ---
        expected_temp = metadata.get('expected_temperature_units', 'Imperial')
        try:
            if current_temp == expected_temp:
                score += 20
                feedback_parts.append("Temperature units changed to Fahrenheit")
            else:
                feedback_parts.append(
                    f"Temperature units is '{current_temp}', "
                    f"expected '{expected_temp}' (Fahrenheit)"
                )
        except Exception as e:
            feedback_parts.append(f"Temperature units check error: {e}")

        # --- Criterion 3: GPS coordinate format => "1" (DMS) — 20 pts ---
        expected_gps = metadata.get('expected_gps_format', '1')
        try:
            current_gps = result.get('gps_format', '')
            if current_gps == expected_gps:
                score += 20
                feedback_parts.append("GPS format changed to DMS")
            else:
                feedback_parts.append(
                    f"GPS format is '{current_gps}', "
                    f"expected '{expected_gps}' (DMS)"
                )
        except Exception as e:
            feedback_parts.append(f"GPS format check error: {e}")

        # --- Criterion 4: Time format => "1" (12h) — 20 pts ---
        expected_time = metadata.get('expected_time_format', '1')
        try:
            current_time = result.get('time_format', '')
            if current_time == expected_time:
                score += 20
                feedback_parts.append("Time format changed to 12h")
            else:
                feedback_parts.append(
                    f"Time format is '{current_time}', "
                    f"expected '{expected_time}' (12h)"
                )
        except Exception as e:
            feedback_parts.append(f"Time format check error: {e}")

        # --- Criterion 5: Color scheme => "2" (Night mode) — 20 pts ---
        expected_theme = metadata.get('expected_color_scheme', '2')
        try:
            current_theme = result.get('color_scheme', '')
            if current_theme == expected_theme:
                score += 20
                feedback_parts.append("Color scheme changed to Night mode")
            else:
                feedback_parts.append(
                    f"Color scheme is '{current_theme}', "
                    f"expected '{expected_theme}' (Night mode)"
                )
        except Exception as e:
            feedback_parts.append(f"Color scheme check error: {e}")

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
            "feedback": "Result file /data/local/tmp/prepare_international_trip_result.json not found"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file is not valid JSON: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verifier error: {str(e)}"
        }
