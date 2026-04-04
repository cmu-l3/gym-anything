#!/usr/bin/env python3
"""
Verifier for blade_root_transition_design task.
Checks if the agent correctly designed a blade with a cylindrical root (NACA 0099)
and an aerodynamic tip (NACA 4412) and exported the geometry.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_blade_root_transition_design(traj, env_info, task_info):
    """
    Verify the blade design task.
    
    Criteria:
    1. Geometry export file exists and was created during the task.
    2. Project file exists and was created during the task.
    3. Geometry file contains reference to Root Foil (0099) and Tip Foil (4412).
    4. Root chord (at r=0) is approx 1.2m.
    5. Tip chord (at r=12) is approx 0.6m.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_root_foil = metadata.get('root_foil', '0099')
    expected_tip_foil = metadata.get('tip_foil', '4412')
    expected_root_chord = metadata.get('root_chord', 1.2)
    expected_tip_chord = metadata.get('tip_chord', 0.6)
    tolerance = metadata.get('tolerance', 0.1)

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify File Existence & Timing (Anti-Gaming)
    geo_exists = result.get("geometry_file_exists", False)
    geo_fresh = result.get("geometry_created_during_task", False)
    proj_exists = result.get("project_file_exists", False)
    proj_fresh = result.get("project_created_during_task", False)

    if geo_exists and geo_fresh:
        score += 20
        feedback_parts.append("Geometry file created successfully.")
    elif geo_exists:
        feedback_parts.append("Geometry file exists but looks old (pre-task).")
    else:
        feedback_parts.append("Geometry file not found.")

    if proj_exists and proj_fresh:
        score += 10
        feedback_parts.append("Project file saved.")
    else:
        feedback_parts.append("Project file not saved.")

    # Stop here if primary evidence is missing
    if not geo_exists or not geo_fresh:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 3. Analyze Geometry File Content
    # We copy the geometry file from the container to inspect it
    temp_geo = tempfile.NamedTemporaryFile(delete=False, suffix='.dat')
    file_content = ""
    try:
        copy_from_env(metadata.get('output_geometry'), temp_geo.name)
        with open(temp_geo.name, 'r', errors='ignore') as f:
            file_content = f.read()
    except Exception as e:
        feedback_parts.append(f"Could not read geometry file: {e}")
    finally:
        if os.path.exists(temp_geo.name):
            os.unlink(temp_geo.name)

    # 4. Check Airfoils in Content
    # QBlade export typically names airfoils like "NACA_0099" or just "0099"
    has_root_foil = expected_root_foil in file_content or "99" in file_content
    has_tip_foil = expected_tip_foil in file_content
    
    if has_root_foil:
        score += 20
        feedback_parts.append(f"Root airfoil ({expected_root_foil}) found.")
    else:
        feedback_parts.append(f"Root airfoil ({expected_root_foil}) NOT found in geometry.")

    if has_tip_foil:
        score += 20
        feedback_parts.append(f"Tip airfoil ({expected_tip_foil}) found.")
    else:
        feedback_parts.append(f"Tip airfoil ({expected_tip_foil}) NOT found in geometry.")

    # 5. Check Geometric Dimensions (Parsing)
    # The file is typically whitespace or tab separated.
    # We look for lines containing numbers.
    # Strategy: Find max chord and min chord, or specific positions if labeled.
    # Simpler strategy: Scan for the specific numbers 1.2 and 0.6 roughly associated with positions.
    
    # Let's try to parse lines to find stations
    lines = file_content.split('\n')
    found_root_chord = False
    found_tip_chord = False
    
    # Heuristic: Check if specific number combinations exist on the same line
    for line in lines:
        parts = line.split()
        if len(parts) < 2: continue
        
        # Check for numeric values in line
        try:
            # Look for Pos 0.0 and Chord 1.2
            # Allow some flexibility in column order, just look for the numbers in the line
            nums = []
            for p in parts:
                try:
                    nums.append(float(p))
                except ValueError:
                    pass
            
            # Check for Root: Pos ~0.0, Chord ~1.2
            if any(abs(n - 0.0) < 0.1 for n in nums) and any(abs(n - expected_root_chord) < tolerance for n in nums):
                found_root_chord = True
            
            # Check for Tip: Pos ~12.0, Chord ~0.6
            if any(abs(n - 12.0) < 0.1 for n in nums) and any(abs(n - expected_tip_chord) < tolerance for n in nums):
                found_tip_chord = True
                
        except Exception:
            continue

    if found_root_chord:
        score += 15
        feedback_parts.append("Root chord dimensions verified.")
    else:
        feedback_parts.append("Root chord dimensions (1.2m at pos 0) not clearly found.")

    if found_tip_chord:
        score += 15
        feedback_parts.append("Tip chord dimensions verified.")
    else:
        feedback_parts.append("Tip chord dimensions (0.6m at pos 12) not clearly found.")

    # Pass/Fail determination
    # Max Score: 20 (File) + 10 (Project) + 20 (RootFoil) + 20 (TipFoil) + 15 (RootChord) + 15 (TipChord) = 100
    # Threshold: 75 (Must have files + correct airfoils + at least one dimension correct)
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }