#!/usr/bin/env python3
"""Verifier for overnight_refuse_collection task.

Scenario: Configure Sygic GPS for an overnight municipal refuse truck — night mode,
avoid highways, shortest route, truck profile, Fahrenheit temperature.

Scoring (100 points):
- GATE: New vehicle profile must exist
- Criterion 1: Truck profile name contains 'refuse', 'truck', or 'waste' (20 pts)
- Criterion 2: Vehicle type is TRUCK (15 pts)
- Criterion 3: Fuel=DIESEL, Year=2018, Emission=EURO6 (15 pts: 5 each)
- Criterion 4: Truck profile is selected as active (15 pts)
- Criterion 5: Route compute set to Shortest ("0") (15 pts)
- Criterion 6: Highways/motorways are avoided (true) (10 pts)
- Criterion 7: App theme set to Night ("2") (5 pts)
- Criterion 8: Temperature units set to Imperial (Fahrenheit) (5 pts)

Pass threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_overnight_refuse_collection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/data/local/tmp/overnight_refuse_collection_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        parts = []

        # GATE: Must have created at least one new vehicle profile
        if result.get('new_vehicles', 0) <= 0 and not result.get('truck_exists', False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new vehicle profile created — refuse truck profile is missing"
            }

        # Criterion 1: Truck name (20 pts)
        try:
            name = result.get('truck_name', '').lower()
            if any(kw in name for kw in ('refuse', 'truck', 'waste')):
                score += 20
                parts.append(f"Truck profile '{result.get('truck_name')}' created (20/20)")
            elif result.get('truck_exists'):
                score += 5
                parts.append(f"Vehicle created but name '{result.get('truck_name')}' not 'refuse/truck/waste' (5/20)")
            else:
                parts.append("No matching truck profile found (0/20)")
        except Exception as e:
            parts.append(f"Name check error: {e}")

        # Criterion 2: Vehicle type is TRUCK (15 pts)
        try:
            vtype = result.get('truck_type', '').upper()
            if vtype == 'TRUCK':
                score += 15
                parts.append("Vehicle type is TRUCK (15/15)")
            elif vtype:
                parts.append(f"Vehicle type is '{vtype}', expected TRUCK (0/15)")
            else:
                parts.append("Vehicle type not set (0/15)")
        except Exception as e:
            parts.append(f"Type check error: {e}")

        # Criterion 3: Fuel=DIESEL, Year=2018, Emission=EURO6 (15 pts: 5 each)
        try:
            sub = 0
            fuel = result.get('truck_fuel', '').upper()
            if fuel == 'DIESEL':
                sub += 5
                parts.append("Fuel: DIESEL (5/5)")
            elif fuel:
                parts.append(f"Fuel: '{fuel}', expected DIESEL (0/5)")

            year = str(result.get('truck_year', ''))
            if year == '2018':
                sub += 5
                parts.append("Year: 2018 (5/5)")
            elif year:
                parts.append(f"Year: {year}, expected 2018 (0/5)")

            emission = result.get('truck_emission', '').upper()
            if 'EURO6' in emission or 'EURO_6' in emission:
                sub += 5
                parts.append("Emission: EURO6 (5/5)")
            elif emission:
                parts.append(f"Emission: '{emission}', expected EURO6 (0/5)")

            score += sub
        except Exception as e:
            parts.append(f"Details check error: {e}")

        # Criterion 4: Truck profile is active (15 pts)
        try:
            selected = str(result.get('selected_vehicle_id', ''))
            truck_id = str(result.get('truck_id', ''))
            initial = str(result.get('initial_selected_id', ''))
            if truck_id and selected == truck_id:
                score += 15
                parts.append("Truck profile is active (15/15)")
            elif selected != initial:
                score += 5
                parts.append(f"Active profile changed but not to truck (5/15)")
            else:
                parts.append("Truck profile not set as active (0/15)")
        except Exception as e:
            parts.append(f"Active profile check error: {e}")

        # Criterion 5: Route compute = Shortest ("0") (15 pts)
        try:
            rc = str(result.get('route_compute', ''))
            if rc == '0':
                score += 15
                parts.append("Route: Shortest (15/15)")
            else:
                parts.append(f"Route compute: '{rc}', expected '0' (Shortest) (0/15)")
        except Exception as e:
            parts.append(f"Route compute check error: {e}")

        # Criterion 6: Highways avoided (true) (10 pts)
        try:
            highways = result.get('avoid_highways', '').lower()
            if highways == 'true':
                score += 10
                parts.append("Highways: avoided (10/10)")
            else:
                parts.append(f"Avoid highways: '{highways}', expected 'true' (0/10)")
        except Exception as e:
            parts.append(f"Highways check error: {e}")

        # Criterion 7: App theme = Night ("2") (5 pts)
        try:
            theme = str(result.get('app_theme', ''))
            if theme == '2':
                score += 5
                parts.append("Theme: Night mode (5/5)")
            else:
                parts.append(f"Theme: '{theme}', expected '2' (Night) (0/5)")
        except Exception as e:
            parts.append(f"Theme check error: {e}")

        # Criterion 8: Temperature = Imperial/Fahrenheit (5 pts)
        try:
            temp = result.get('temperature_units', '').lower()
            if 'imperial' in temp or 'fahrenheit' in temp:
                score += 5
                parts.append("Temperature: Imperial/Fahrenheit (5/5)")
            else:
                parts.append(f"Temperature: '{result.get('temperature_units', '')}', expected 'Imperial' (0/5)")
        except Exception as e:
            parts.append(f"Temperature check error: {e}")

        return {
            "passed": score >= 65,
            "score": min(score, 100),
            "feedback": " | ".join(parts) or "No criteria met"
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
