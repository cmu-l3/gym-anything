#!/usr/bin/env python3
"""Verifier for luxury_chauffeur_setup task.

Scenario: Configure Sygic GPS for a premium executive chauffeur service —
arrive-in-direction, night theme, tolls not avoided, compass always on, DMS GPS format.

The task is pure settings configuration — no vehicle profile creation required.
The gate check is that at least one setting changed from its baseline.

Scoring (100 points):
- GATE: At least one setting changed from baseline (otherwise score=0)
- Criterion 1: Arrive-in-driving-direction enabled (true) (25 pts)
- Criterion 2: App theme set to Night ("2") (25 pts)
- Criterion 3: Toll roads NOT avoided (false) (20 pts)
- Criterion 4: Compass always on enabled (true) (20 pts)
- Criterion 5: GPS coordinate format set to DMS ("1") (10 pts)

Pass threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_luxury_chauffeur_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/data/local/tmp/luxury_chauffeur_setup_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        parts = []

        # GATE: Check that at least one setting differs from baseline
        # This rejects the do-nothing case where agent made no changes
        arrive = result.get('arrive_in_direction', '').lower()
        theme = str(result.get('app_theme', ''))
        tolls = result.get('avoid_tolls', '').lower()
        compass = result.get('compass_always_on', '').lower()
        gps_fmt = str(result.get('gps_format', ''))

        b_arrive = result.get('baseline_arrive', 'false').lower()
        b_theme = str(result.get('baseline_theme', '0'))
        b_tolls = result.get('baseline_tolls', 'true').lower()
        b_compass = result.get('baseline_compass', 'false').lower()
        b_gps = str(result.get('baseline_gps', '0'))

        any_changed = (
            arrive != b_arrive or
            theme != b_theme or
            tolls != b_tolls or
            compass != b_compass or
            gps_fmt != b_gps
        )

        if not any_changed:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No settings were changed from the starting state — agent made no changes"
            }

        # Criterion 1: Arrive-in-direction enabled (25 pts)
        try:
            if arrive == 'true':
                score += 25
                parts.append("Arrive-in-direction: enabled (25/25)")
            else:
                parts.append(f"Arrive-in-direction: '{arrive}', expected 'true' (0/25)")
        except Exception as e:
            parts.append(f"Arrive-in-direction check error: {e}")

        # Criterion 2: App theme = Night ("2") (25 pts)
        try:
            if theme == '2':
                score += 25
                parts.append("Theme: Night mode (25/25)")
            else:
                parts.append(f"Theme: '{theme}', expected '2' (Night) (0/25)")
        except Exception as e:
            parts.append(f"Theme check error: {e}")

        # Criterion 3: Toll roads NOT avoided (false) (20 pts)
        try:
            if tolls == 'false':
                score += 20
                parts.append("Toll roads: NOT avoided (20/20)")
            else:
                parts.append(f"Avoid tolls: '{tolls}', expected 'false' (toll roads should be allowed) (0/20)")
        except Exception as e:
            parts.append(f"Toll roads check error: {e}")

        # Criterion 4: Compass always on (20 pts)
        try:
            if compass == 'true':
                score += 20
                parts.append("Compass always on: enabled (20/20)")
            else:
                parts.append(f"Compass: '{compass}', expected 'true' (0/20)")
        except Exception as e:
            parts.append(f"Compass check error: {e}")

        # Criterion 5: GPS format = DMS ("1") (10 pts)
        try:
            if gps_fmt == '1':
                score += 10
                parts.append("GPS format: DMS (10/10)")
            else:
                parts.append(f"GPS format: '{gps_fmt}', expected '1' (DMS) (0/10)")
        except Exception as e:
            parts.append(f"GPS format check error: {e}")

        return {
            "passed": score >= 65,
            "score": min(score, 100),
            "feedback": " | ".join(parts) or "No criteria met"
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
