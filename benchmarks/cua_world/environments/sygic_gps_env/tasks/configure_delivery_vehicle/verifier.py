#!/usr/bin/env python3
"""Verifier for configure_delivery_vehicle task.

Scoring (100 points):
- Criterion 1: New vehicle profile created with name containing 'Delivery' or 'Van' (20 pts)
- Criterion 2: Vehicle type is VAN (15 pts)
- Criterion 3: Fuel type is DIESEL and production year is 2022, emission is EURO6 (15 pts)
- Criterion 4: Delivery Van profile is selected as active (20 pts)
- Criterion 5: Route compute set to Shortest (value "0") (15 pts)
- Criterion 6: Toll roads NOT avoided (false) AND arrive-in-direction enabled (true) (15 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_delivery_vehicle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/data/local/tmp/configure_delivery_vehicle_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []

        # GATE: If no new vehicles were created, no work was done
        if result.get('new_vehicles', 0) <= 0 and not result.get('delivery_van_exists', False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new vehicle profile created"
            }

        # Criterion 1: New vehicle profile exists with correct name (20 pts)
        try:
            if result.get('delivery_van_exists', False):
                name = result.get('delivery_van_name', '').lower()
                if 'delivery' in name or 'van' in name:
                    score += 20
                    feedback_parts.append(f"Vehicle profile '{result.get('delivery_van_name')}' created")
                else:
                    score += 5  # Partial: new profile but wrong name
                    feedback_parts.append(f"Vehicle created but name '{result.get('delivery_van_name')}' doesn't contain 'Delivery' or 'Van'")
            else:
                feedback_parts.append("No 'Delivery Van' profile found")
        except Exception as e:
            feedback_parts.append(f"Vehicle name check error: {e}")

        # Criterion 2: Vehicle type is VAN (15 pts)
        try:
            dv_type = result.get('delivery_van_type', '').upper()
            if dv_type == 'VAN':
                score += 15
                feedback_parts.append("Vehicle type is VAN")
            elif dv_type:
                feedback_parts.append(f"Vehicle type is '{dv_type}', expected VAN")
            else:
                feedback_parts.append("Vehicle type not set")
        except Exception as e:
            feedback_parts.append(f"Vehicle type check error: {e}")

        # Criterion 3: Fuel=DIESEL, year=2022, emission=EURO6 (15 pts total: 5 each)
        try:
            sub_score = 0
            dv_fuel = result.get('delivery_van_fuel', '').upper()
            if dv_fuel == 'DIESEL':
                sub_score += 5
                feedback_parts.append("Fuel type is DIESEL")
            elif dv_fuel:
                feedback_parts.append(f"Fuel type is '{dv_fuel}', expected DIESEL")

            dv_year = str(result.get('delivery_van_year', ''))
            if dv_year == '2022':
                sub_score += 5
                feedback_parts.append("Production year is 2022")
            elif dv_year:
                feedback_parts.append(f"Production year is {dv_year}, expected 2022")

            dv_emission = result.get('delivery_van_emission', '').upper()
            if 'EURO6' in dv_emission or 'EURO_6' in dv_emission:
                sub_score += 5
                feedback_parts.append("Emission category is EURO6")
            elif dv_emission:
                feedback_parts.append(f"Emission is '{dv_emission}', expected EURO6")

            score += sub_score
        except Exception as e:
            feedback_parts.append(f"Vehicle details check error: {e}")

        # Criterion 4: Delivery Van is selected as active profile (20 pts)
        try:
            selected_id = str(result.get('selected_vehicle_id', ''))
            delivery_van_id = str(result.get('delivery_van_id', ''))
            initial_selected = str(result.get('initial_selected_id', ''))

            if delivery_van_id and selected_id == delivery_van_id:
                score += 20
                feedback_parts.append("Delivery Van is the active profile")
            elif selected_id != initial_selected:
                score += 5  # Partial: selection changed but not to van
                feedback_parts.append(f"Active profile changed but not to Delivery Van (selected={selected_id}, van={delivery_van_id})")
            else:
                feedback_parts.append("Delivery Van is not the active profile")
        except Exception as e:
            feedback_parts.append(f"Active profile check error: {e}")

        # Criterion 5: Route compute set to Shortest ("0") (15 pts)
        try:
            route_compute = str(result.get('route_compute', ''))
            if route_compute == '0':
                score += 15
                feedback_parts.append("Route compute set to Shortest")
            else:
                feedback_parts.append(f"Route compute is '{route_compute}', expected '0' (Shortest)")
        except Exception as e:
            feedback_parts.append(f"Route compute check error: {e}")

        # Criterion 6: Toll roads allowed (false) AND arrive-in-direction enabled (true) (15 pts: 7+8)
        try:
            sub_score = 0
            avoid_tolls = result.get('avoid_tolls', '').lower()
            if avoid_tolls == 'false':
                sub_score += 7
                feedback_parts.append("Toll roads allowed")
            else:
                feedback_parts.append(f"Avoid tolls is '{avoid_tolls}', expected 'false'")

            arrive_dir = result.get('arrive_in_direction', '').lower()
            if arrive_dir == 'true':
                sub_score += 8
                feedback_parts.append("Arrive in direction enabled")
            else:
                feedback_parts.append(f"Arrive in direction is '{arrive_dir}', expected 'true'")

            score += sub_score
        except Exception as e:
            feedback_parts.append(f"Route options check error: {e}")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met"
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}
