#!/usr/bin/env python3
"""Verifier for school_bus_safety_setup task.

Scenario: Configure Sygic GPS for a school bus per district safety policy —
arrive-in-direction, lane guidance, ferry avoidance, miles, bus vehicle profile.

Scoring (100 points):
- GATE: New vehicle profile must exist
- Criterion 1: Bus profile name contains 'school' or 'bus' (20 pts)
- Criterion 2: Vehicle type is BUS (15 pts)
- Criterion 3: Fuel=DIESEL, Year=2020, Emission=EURO6 (15 pts: 5 each)
- Criterion 4: Bus profile is selected as active (15 pts)
- Criterion 5: Arrive-in-driving-direction enabled (true) (15 pts)
- Criterion 6: Lane guidance enabled (true) (10 pts)
- Criterion 7: Ferries avoided (true) (5 pts)
- Criterion 8: Distance units = Miles ("0") (5 pts)

Pass threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_school_bus_safety_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/data/local/tmp/school_bus_safety_setup_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        parts = []

        # GATE: Must have created at least one new vehicle profile
        if result.get('new_vehicles', 0) <= 0 and not result.get('bus_exists', False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new vehicle profile created — school bus profile is missing"
            }

        # Criterion 1: Bus name contains 'school' or 'bus' (20 pts)
        try:
            name = result.get('bus_name', '').lower()
            if any(kw in name for kw in ('school', 'bus')):
                score += 20
                parts.append(f"Bus profile '{result.get('bus_name')}' created (20/20)")
            elif result.get('bus_exists'):
                score += 5
                parts.append(f"Vehicle created but name '{result.get('bus_name')}' not 'school/bus' (5/20)")
            else:
                parts.append("No matching bus profile found (0/20)")
        except Exception as e:
            parts.append(f"Name check error: {e}")

        # Criterion 2: Vehicle type is BUS (15 pts)
        try:
            vtype = result.get('bus_type', '').upper()
            if vtype == 'BUS':
                score += 15
                parts.append("Vehicle type is BUS (15/15)")
            elif vtype:
                parts.append(f"Vehicle type is '{vtype}', expected BUS (0/15)")
            else:
                parts.append("Vehicle type not set (0/15)")
        except Exception as e:
            parts.append(f"Type check error: {e}")

        # Criterion 3: Fuel=DIESEL, Year=2020, Emission=EURO6 (15 pts: 5 each)
        try:
            sub = 0
            fuel = result.get('bus_fuel', '').upper()
            if fuel == 'DIESEL':
                sub += 5
                parts.append("Fuel: DIESEL (5/5)")
            elif fuel:
                parts.append(f"Fuel: '{fuel}', expected DIESEL (0/5)")

            year = str(result.get('bus_year', ''))
            if year == '2020':
                sub += 5
                parts.append("Year: 2020 (5/5)")
            elif year:
                parts.append(f"Year: {year}, expected 2020 (0/5)")

            emission = result.get('bus_emission', '').upper()
            if 'EURO6' in emission or 'EURO_6' in emission:
                sub += 5
                parts.append("Emission: EURO6 (5/5)")
            elif emission:
                parts.append(f"Emission: '{emission}', expected EURO6 (0/5)")

            score += sub
        except Exception as e:
            parts.append(f"Details check error: {e}")

        # Criterion 4: Bus profile is active (15 pts)
        try:
            selected = str(result.get('selected_vehicle_id', ''))
            bus_id = str(result.get('bus_id', ''))
            initial = str(result.get('initial_selected_id', ''))
            if bus_id and selected == bus_id:
                score += 15
                parts.append("School Bus profile is active (15/15)")
            elif selected != initial:
                score += 5
                parts.append(f"Active profile changed but not to bus (5/15)")
            else:
                parts.append("School Bus profile not set as active (0/15)")
        except Exception as e:
            parts.append(f"Active profile check error: {e}")

        # Criterion 5: Arrive-in-direction enabled (15 pts)
        try:
            arrive = result.get('arrive_in_direction', '').lower()
            if arrive == 'true':
                score += 15
                parts.append("Arrive-in-direction: enabled (15/15)")
            else:
                parts.append(f"Arrive-in-direction: '{arrive}', expected 'true' (0/15)")
        except Exception as e:
            parts.append(f"Arrive-in-direction check error: {e}")

        # Criterion 6: Lane guidance enabled (10 pts)
        try:
            lane = result.get('lane_guidance', '').lower()
            if lane == 'true':
                score += 10
                parts.append("Lane guidance: enabled (10/10)")
            else:
                parts.append(f"Lane guidance: '{lane}', expected 'true' (0/10)")
        except Exception as e:
            parts.append(f"Lane guidance check error: {e}")

        # Criterion 7: Ferries avoided (5 pts)
        try:
            ferries = result.get('avoid_ferries', '').lower()
            if ferries == 'true':
                score += 5
                parts.append("Ferries: avoided (5/5)")
            else:
                parts.append(f"Avoid ferries: '{ferries}', expected 'true' (0/5)")
        except Exception as e:
            parts.append(f"Ferries check error: {e}")

        # Criterion 8: Distance units = Miles ("0") (5 pts)
        try:
            dist = str(result.get('distance_units', ''))
            if dist == '0':
                score += 5
                parts.append("Distance: Miles (5/5)")
            else:
                parts.append(f"Distance units: '{dist}', expected '0' (Miles) (0/5)")
        except Exception as e:
            parts.append(f"Distance check error: {e}")

        return {
            "passed": score >= 65,
            "score": min(score, 100),
            "feedback": " | ".join(parts) or "No criteria met"
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
