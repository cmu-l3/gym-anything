#!/usr/bin/env python3
"""
Verifier for set_flap_deflection task.
Checks exported airfoil coordinate files for correct NACA 4415 base
and proper trailing edge flap deflection.
"""
import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
HINGE_X = 0.75
TARGET_ANGLE_DEG = 10.0
ANGLE_TOLERANCE = 3.0  # degrees
COORD_TOLERANCE = 0.01

def verify_set_flap_deflection(traj, env_info, task_info):
    """
    Verify the agent generated a NACA 4415 and a flap-deflected version.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    original_path = metadata.get('original_file', '/home/ga/Documents/airfoils/naca4415_original.dat')
    modified_path = metadata.get('modified_file', '/home/ga/Documents/airfoils/naca4415_flap10.dat')

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []

    # 2. Check File Existence and Creation (Anti-gaming)
    orig_info = result.get("original_file", {})
    mod_info = result.get("modified_file", {})

    if not orig_info.get("exists") or not mod_info.get("exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "One or both output files are missing. Task requires 'naca4415_original.dat' and 'naca4415_flap10.dat'."
        }

    # Files exist (20 pts)
    score += 20
    feedback_parts.append("Both output files exist")

    # Files created during task (10 pts)
    if orig_info.get("created_during_task") and mod_info.get("created_during_task"):
        score += 10
        feedback_parts.append("Files created during task")
    else:
        feedback_parts.append("Warning: Files have old timestamps")

    # 3. Retrieve and Parse Coordinate Files
    def get_coords(remote_path):
        """Helper to fetch and parse .dat file"""
        tfile = tempfile.NamedTemporaryFile(delete=False, suffix='.dat')
        try:
            copy_from_env(remote_path, tfile.name)
            coords = []
            with open(tfile.name, 'r') as f:
                lines = f.readlines()
            
            # Simple parsing: skip header, look for 2 floats
            valid_lines = 0
            for line in lines:
                parts = line.strip().split()
                if len(parts) >= 2:
                    try:
                        x = float(parts[0])
                        y = float(parts[1])
                        # Filter valid airfoil range
                        if -0.1 <= x <= 1.1 and -0.5 <= y <= 0.5:
                            coords.append((x, y))
                            valid_lines += 1
                    except ValueError:
                        continue
            return coords, valid_lines
        except Exception:
            return [], 0
        finally:
            if os.path.exists(tfile.name):
                os.unlink(tfile.name)

    orig_coords, orig_count = get_coords(original_path)
    mod_coords, mod_count = get_coords(modified_path)

    if orig_count < 20 or mod_count < 20:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Files contain insufficient data (Original: {orig_count}, Modified: {mod_count} points)."
        }

    score += 10
    feedback_parts.append("Valid coordinate data found")

    # 4. Geometric Verification Logic
    
    # Sort by x for easier comparison (assuming standard format wrapping TE->LE->TE or LE->TE)
    # To compare robustly, we separate upper and lower surfaces or just nearest neighbor match.
    # Here we define a simple function to split airfoil roughly at x-axis or by index if ordered.
    # A robust metric: "Forward portion identity"
    
    # Check A: Forward Identity (x < 0.7)
    # Find points in modified that match points in original
    matched_points = 0
    checked_points = 0
    
    for mx, my in mod_coords:
        if mx < 0.70:
            checked_points += 1
            # Look for close match in original
            # Simple linear scan is fine for small N (<500)
            is_match = False
            for ox, oy in orig_coords:
                dist = math.sqrt((mx - ox)**2 + (my - oy)**2)
                if dist < 0.005: # Tolerance for slight numerical noise
                    is_match = True
                    break
            if is_match:
                matched_points += 1
    
    forward_match_ratio = matched_points / max(1, checked_points)
    
    if forward_match_ratio > 0.9:
        score += 20
        feedback_parts.append("Forward airfoil section is preserved")
    else:
        feedback_parts.append(f"Forward section mismatch (match ratio: {forward_match_ratio:.2f})")

    # Check B: Aft Deflection (x > 0.8)
    # We expect points to be DIFFERENT here
    # Specifically, trailing edge (x ~ 1.0) should be lower (higher y if coord system inverted, usually lower for positive flap)
    # Positive flap = downward deflection.
    # Let's find the trailing edge point (approx max x)
    
    def find_te(coords):
        # TE is usually point with max x
        te = max(coords, key=lambda p: p[0])
        return te

    orig_te = find_te(orig_coords)
    mod_te = find_te(mod_coords)
    
    # Calculate deflection
    # Hinge is at (0.75, y_c). For NACA 4415, camber line y_c at 0.75 is approx:
    # m=0.04, p=0.4. x>p formula: y_c = m/(1-p)^2 * ( (1-2p) + 2px - x^2 )
    # x=0.75 -> y_c approx 0.02
    # Simple check: Compare angle of vector from Hinge to TE
    
    hinge_est = (0.75, 0.02) # Approximate
    
    def angle_from_hinge(p):
        dx = p[0] - hinge_est[0]
        dy = p[1] - hinge_est[1]
        return math.degrees(math.atan2(dy, dx))

    angle_orig = angle_from_hinge(orig_te)
    angle_mod = angle_from_hinge(mod_te)
    
    # Deflection = angle_orig - angle_mod (if positive flap moves TE down, angle decreases/becomes more negative)
    # Standard: +y is up. TE moves down -> y decreases. Atan2 decreases. 
    # So angle_orig > angle_mod.
    # Diff should be approx 10 degrees.
    
    measured_deflection = angle_orig - angle_mod
    
    logger.info(f"TE Analysis: Orig {orig_te}, Mod {mod_te}")
    logger.info(f"Angles: Orig {angle_orig:.2f}, Mod {angle_mod:.2f}, Diff {measured_deflection:.2f}")

    if 5.0 <= measured_deflection <= 15.0:
        score += 30
        feedback_parts.append(f"Flap deflection angle correct ({measured_deflection:.1f}°)")
    elif 1.0 < measured_deflection < 20.0:
        score += 15
        feedback_parts.append(f"Flap deflected, but angle inaccurate ({measured_deflection:.1f}°)")
    else:
        feedback_parts.append(f"Flap deflection not detected or wrong direction (Diff: {measured_deflection:.1f}°)")

    # 5. Check Output Distinctness
    if orig_count == mod_count and measured_deflection < 0.1:
        feedback_parts.append("Error: Original and Modified files appear identical")
        score = min(score, 40) # Cap score if user just exported same file twice

    # 6. Check App Running
    if result.get("app_was_running"):
        score += 10
        feedback_parts.append("QBlade was running")

    passed = score >= 60 and (5.0 <= measured_deflection <= 15.0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }