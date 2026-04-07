#!/usr/bin/env python3
"""Verifier for courier_urban_delivery task.

Scenario: Configure Sygic GPS for an urban courier driver using a delivery van.

Scoring (100 points):
- Criterion 1 (GATE): New vehicle profile created (0 pts, gate only)
- Criterion 2: Van profile named correctly (contains 'courier', 'city', or 'van') (20 pts)
- Criterion 3: Vehicle type is VAN (15 pts)
- Criterion 4: Fuel=DIESEL, year=2021, emission=EURO6 (15 pts: 5 each)
- Criterion 5: New van profile is selected as active (15 pts)
- Criterion 6: Route compute set to Shortest ("0") (15 pts)
- Criterion 7: Toll roads avoided (true) (10 pts)
- Criterion 8: Distance units set to Km ("1") (5 pts)
- Criterion 9: Arrive-in-driving-direction enabled (true) (5 pts)

Pass threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_courier_urban_delivery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/data/local/tmp/courier_urban_delivery_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)

        score = 0
        parts = []

        # GATE: Must have created at least one new vehicle profile
        if result.get('new_vehicles', 0) <= 0 and not result.get('van_exists', False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new vehicle profile created — delivery van profile is missing"
            }

        # Criterion 2: Van name contains 'courier', 'city', or 'van' (20 pts)
        try:
            name = result.get('van_name', '').lower()
            if any(kw in name for kw in ('courier', 'city', 'van')):
                score += 20
                parts.append(f"Van profile '{result.get('van_name')}' created (20/20)")
            elif result.get('van_exists'):
                score += 5
                parts.append(f"Vehicle created but name '{result.get('van_name')}' doesn't match 'courier/city/van' (5/20)")
            else:
                parts.append("No matching van profile found (0/20)")
        except Exception as e:
            parts.append(f"Name check error: {e}")

        # Criterion 3: Vehicle type is VAN (15 pts)
        try:
            vtype = result.get('van_type', '').upper()
            if vtype == 'VAN':
                score += 15
                parts.append("Vehicle type is VAN (15/15)")
            elif vtype:
                parts.append(f"Vehicle type is '{vtype}', expected VAN (0/15)")
            else:
                parts.append("Vehicle type not set (0/15)")
        except Exception as e:
            parts.append(f"Type check error: {e}")

        # Criterion 4: Fuel=DIESEL, year=2021, emission=EURO6 (15 pts: 5 each)
        try:
            sub = 0
            fuel = result.get('van_fuel', '').upper()
            if fuel == 'DIESEL':
                sub += 5
                parts.append("Fuel: DIESEL (5/5)")
            elif fuel:
                parts.append(f"Fuel: '{fuel}', expected DIESEL (0/5)")

            year = str(result.get('van_year', ''))
            if year == '2021':
                sub += 5
                parts.append("Year: 2021 (5/5)")
            elif year:
                parts.append(f"Year: {year}, expected 2021 (0/5)")

            emission = result.get('van_emission', '').upper()
            if 'EURO6' in emission or 'EURO_6' in emission:
                sub += 5
                parts.append("Emission: EURO6 (5/5)")
            elif emission:
                parts.append(f"Emission: '{emission}', expected EURO6 (0/5)")

            score += sub
        except Exception as e:
            parts.append(f"Details check error: {e}")

        # Criterion 5: Van profile is selected as active (15 pts)
        try:
            selected = str(result.get('selected_vehicle_id', ''))
            van_id = str(result.get('van_id', ''))
            initial = str(result.get('initial_selected_id', ''))
            if van_id and selected == van_id:
                score += 15
                parts.append("Van profile is active (15/15)")
            elif selected != initial:
                score += 5
                parts.append(f"Active profile changed but not to van (5/15)")
            else:
                parts.append("Van profile not set as active (0/15)")
        except Exception as e:
            parts.append(f"Active profile check error: {e}")

        # Criterion 6: Route compute = Shortest ("0") (15 pts)
        try:
            rc = str(result.get('route_compute', ''))
            if rc == '0':
                score += 15
                parts.append("Route: Shortest (15/15)")
            else:
                parts.append(f"Route compute: '{rc}', expected '0' (Shortest) (0/15)")
        except Exception as e:
            parts.append(f"Route compute check error: {e}")

        # Criterion 7: Toll roads avoided (true) (10 pts)
        try:
            tolls = result.get('avoid_tolls', '').lower()
            if tolls == 'true':
                score += 10
                parts.append("Toll roads: avoided (10/10)")
            else:
                parts.append(f"Toll roads: '{tolls}', expected 'true' (0/10)")
        except Exception as e:
            parts.append(f"Toll roads check error: {e}")

        # Criterion 8: Distance units = Km ("1") (5 pts)
        try:
            dist = str(result.get('distance_units', ''))
            if dist == '1':
                score += 5
                parts.append("Distance: Km (5/5)")
            else:
                parts.append(f"Distance units: '{dist}', expected '1' (Km) (0/5)")
        except Exception as e:
            parts.append(f"Distance check error: {e}")

        # Criterion 9: Arrive-in-direction enabled (5 pts)
        try:
            arrive = result.get('arrive_in_direction', '').lower()
            if arrive == 'true':
                score += 5
                parts.append("Arrive-in-direction: enabled (5/5)")
            else:
                parts.append(f"Arrive-in-direction: '{arrive}', expected 'true' (0/5)")
        except Exception as e:
            parts.append(f"Arrive-in-direction check error: {e}")

        return {
            "passed": score >= 65,
            "score": min(score, 100),
            "feedback": " | ".join(parts) or "No criteria met"
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
