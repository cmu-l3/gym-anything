#!/usr/bin/env python3
"""
Verifier for otv_rideshare_mission_design@1

This verifier heavily relies on the Rocket Equation as an anti-gaming signature.
Because the spacecraft drops mass mid-flight, maneuvers executed later become
cheaper in terms of propellant. If the agent fails to implement the `ChemicalTank` 
or fails to implement the mass drops (DryMass reduction), the Final_Fuel_Mass_kg 
will be mathematically incorrect.

Expected Fuel Math:
- Total wet mass: 1000 kg.
- Maneuver 1 (400->500 km): ~56.0 m/s. Fuel used: ~19.8 kg. Remaining: ~380.2 kg
- Mass Drop 1: Wet mass drops from 980.2 to 830.2 kg.
- Maneuver 2 (500->600 km w/ 2 deg inc change at apogee): ~292.1 m/s.
  Because the spacecraft is now 150 kg lighter, it only uses ~82.4 kg of fuel!
- Remaining Fuel: ~297.8 kg.

If they skip the mass drop, remaining fuel will be ~282.9 kg.

Scoring (100 points total, Pass >= 60):
  - script_created (10)
  - tank_configured (15)
  - mass_drop_implemented (15)
  - payload_a_orbit_valid (15): SMA within 1.5 km of 6871.14
  - payload_b_orbit_valid (20): SMA within 1.5 km of 6971.14, INC within 0.1 of 99.0
  - fuel_mass_valid (25): Final fuel inside physical envelope [294.0, 301.0] kg

Pass condition: Score >= 60 AND payload_b_orbit_valid AND fuel_mass_valid.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_otv_rideshare(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_sma_a = metadata.get('expected_sma_a_km', 6871.14)
    expected_sma_b = metadata.get('expected_sma_b_km', 6971.14)
    expected_inc_b = metadata.get('expected_inc_b_deg', 99.0)
    tol_sma = metadata.get('tolerance_sma_km', 1.5)
    tol_inc = metadata.get('tolerance_inc_deg', 0.1)
    
    # Fuel envelope handles slight variations in targeting approaches (e.g. DC vs analytical)
    fuel_min = metadata.get('fuel_mass_min_kg', 294.0)
    fuel_max = metadata.get('fuel_mass_max_kg', 301.0)

    scores = {
        "script_created": 10,
        "tank_configured": 15,
        "mass_drop_implemented": 15,
        "payload_a_orbit_valid": 15,
        "payload_b_orbit_valid": 20,
        "fuel_mass_valid": 25,
    }

    total_score = 0
    feedback = []
    orbit_b_ok = False
    fuel_ok = False

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Tank Configured
    if task_result.get('tank_configured', False):
        total_score += scores["tank_configured"]
        feedback.append("ChemicalTank configured and attached in script.")
    else:
        feedback.append("ChemicalTank missing or not attached to Spacecraft.")

    # 3. Mass Drop Implemented
    if task_result.get('mass_drop_implemented', False):
        total_score += scores["mass_drop_implemented"]
        feedback.append("DryMass modifications found in script.")
    else:
        feedback.append("DryMass payload deployment reductions not found in script.")

    # Parse numerical results from export
    try:
        sma_a = float(task_result.get('payload_a_sma_km', 0))
    except (ValueError, TypeError):
        sma_a = 0.0

    try:
        sma_b = float(task_result.get('payload_b_sma_km', 0))
    except (ValueError, TypeError):
        sma_b = 0.0

    try:
        inc_b = float(task_result.get('payload_b_inc_deg', 0))
    except (ValueError, TypeError):
        inc_b = 0.0

    try:
        fuel = float(task_result.get('final_fuel_mass_kg', 0))
    except (ValueError, TypeError):
        fuel = 0.0

    # 4. Payload A Orbit
    if abs(sma_a - expected_sma_a) <= tol_sma:
        total_score += scores["payload_a_orbit_valid"]
        feedback.append(f"Payload A orbit correct: {sma_a:.2f} km.")
    else:
        feedback.append(f"Payload A orbit incorrect: {sma_a:.2f} km (Expected ~{expected_sma_a} km).")

    # 5. Payload B Orbit
    if abs(sma_b - expected_sma_b) <= tol_sma and abs(inc_b - expected_inc_b) <= tol_inc:
        total_score += scores["payload_b_orbit_valid"]
        orbit_b_ok = True
        feedback.append(f"Payload B orbit correct: SMA={sma_b:.2f} km, INC={inc_b:.2f} deg.")
    else:
        feedback.append(f"Payload B orbit incorrect: SMA={sma_b:.2f} km, INC={inc_b:.2f} deg.")

    # 6. Fuel Mass (The Cryptographic Rocket Equation check)
    if fuel_min <= fuel <= fuel_max:
        total_score += scores["fuel_mass_valid"]
        fuel_ok = True
        feedback.append(f"Fuel mass physically consistent with mass drops: {fuel:.2f} kg.")
    elif 280.0 <= fuel < fuel_min:
        feedback.append(f"Fuel mass {fuel:.2f} kg is too low. Did you perform the inclination change at the wrong node, or forget to drop payload mass before Phase 2?")
    elif fuel > fuel_max:
        feedback.append(f"Fuel mass {fuel:.2f} kg is too high. Did the spacecraft actually maneuver?")
    else:
        feedback.append(f"Fuel mass {fuel:.2f} kg is outside expected physical bounds.")

    # Determine final pass status
    passed = (total_score >= 60) and orbit_b_ok and fuel_ok

    # Anti-gaming check: if GMAT console run failed, it means they forged the text output
    if task_result.get("console_run_success", "false") != "true":
        passed = False
        total_score = min(total_score, 50)
        feedback.append("CRITICAL FAILURE: Script failed to converge or run via GmatConsole (Possible output forging detected).")

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }