#!/usr/bin/env python3
import json
import math
import os
import sys
import tempfile
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_blind_pilotage_planning(traj, env_info, task_info):
    """
    Verifies the blind_pilotage_planning task.
    
    Verification Logic:
    1. Checks if the scenario directory and files were created.
    2. Validates the geometric calculation of the starting Longitude.
       - Target: 0.6nm East of Nab Tower (-0.9517).
       - Formula: Distance = DeltaLong(min) * cos(Lat)
    3. Validates environment settings (fog, heading).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    nab_lat = metadata.get('nab_tower_lat', 50.6675)
    nab_long = metadata.get('nab_tower_long', -0.9517)
    target_dist = metadata.get('target_distance_nm', 0.6)
    tolerance = metadata.get('target_distance_tolerance_nm', 0.05)

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results. Did the export script run?"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback_lines = []
    
    # Criterion 1: Structure (10 pts)
    if result.get('scenario_exists') and result.get('ownship_ini_exists') and result.get('env_ini_exists'):
        score += 10
        feedback_lines.append("Scenario structure created successfully.")
    else:
        feedback_lines.append("FAIL: Scenario directory or required INI files missing.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback_lines)}

    extracted = result.get('extracted_values', {})
    
    # Criterion 2: Visibility (20 pts)
    try:
        vis = float(extracted.get('visibility', 999))
        if 0.1 <= vis <= 0.3:
            score += 20
            feedback_lines.append(f"Visibility set correctly ({vis} nm).")
        else:
            feedback_lines.append(f"FAIL: Visibility {vis} nm is not dense fog (expected ~0.25).")
    except ValueError:
        feedback_lines.append("FAIL: Visibility value invalid or missing.")

    # Criterion 3: Heading (10 pts)
    try:
        heading = float(extracted.get('own_heading', -1))
        # Accept 0 or 360
        if abs(heading - 0) < 1.0 or abs(heading - 360) < 1.0:
            score += 10
            feedback_lines.append("Heading set correctly to North.")
        else:
            feedback_lines.append(f"FAIL: Heading {heading} is not North.")
    except ValueError:
        feedback_lines.append("FAIL: Heading value invalid or missing.")

    # Criterion 4: Position Accuracy (40 pts) - The Core Math Test
    try:
        agent_lat = float(extracted.get('own_lat', 0))
        agent_long = float(extracted.get('own_long', 0))
        
        # Check Latitude (should be south of tower)
        if 50.55 <= agent_lat <= 50.65:
            # Calculate Cross Track Distance (Departure)
            # Distance (nm) = DeltaLong(degrees) * 60 * cos(Lat_radians)
            # We use the Nab Tower latitude for the cosine term as approximation
            delta_long = agent_long - nab_long # If agent is East, this should be positive (e.g., -0.93 - (-0.95) = +0.02)
            
            lat_rad = math.radians(nab_lat)
            calc_dist = delta_long * 60.0 * math.cos(lat_rad)
            
            # Note: If agent placed it WEST, dist will be negative. We want EAST (positive result).
            # But we'll accept magnitude for partial credit, strictly positive for full.
            
            error = abs(calc_dist - target_dist)
            
            logger.info(f"Agent Long: {agent_long}, Nab Long: {nab_long}, Delta: {delta_long}")
            logger.info(f"Calculated Departure: {calc_dist} nm, Target: {target_dist} nm")

            if error <= tolerance:
                score += 40
                feedback_lines.append(f"Position PRECISE: Calculated offset {calc_dist:.4f} nm matches target {target_dist} nm.")
            elif error <= (tolerance * 2):
                score += 20
                feedback_lines.append(f"Position CLOSE: Calculated offset {calc_dist:.4f} nm (Target {target_dist} nm).")
            else:
                feedback_lines.append(f"FAIL: Position incorrect. Offset {calc_dist:.4f} nm (Expected {target_dist} nm).")
                if calc_dist < 0:
                    feedback_lines.append("Note: You placed the vessel West of the tower; required East.")
        else:
            feedback_lines.append(f"FAIL: Latitude {agent_lat} is not sufficiently South of the tower (expected ~50.60).")
    except ValueError:
        feedback_lines.append("FAIL: Coordinates invalid or missing.")

    # Criterion 5: Briefing Document (10 pts)
    if result.get('briefing_exists'):
        content = result.get('briefing_content', '').lower()
        if '0.6' in content and ('east' in content or 'nab' in content):
            score += 10
            feedback_lines.append("Briefing document exists and contains key details.")
        else:
            score += 5
            feedback_lines.append("Briefing document exists but content is generic.")
    else:
        feedback_lines.append("FAIL: Briefing document missing.")

    # Criterion 6: Syntax/Validity (10 pts)
    # Implicitly checked if we extracted values, giving free points if we got this far
    score += 10
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }