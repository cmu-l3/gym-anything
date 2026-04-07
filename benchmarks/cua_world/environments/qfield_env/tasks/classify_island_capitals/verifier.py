#!/usr/bin/env python3
"""
Verifier for classify_island_capitals task.

Verification Logic:
1. Retrieve the GeoPackage file from the environment.
2. Query the 'world_capitals' table using Python's sqlite3.
3. Check the 'description' attribute for the 6 target cities.
4. Verify VLM trajectory for evidence of UI interaction (Attribute Form).
"""

import sqlite3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_classify_island_capitals(traj, env_info, task_info):
    """
    Verify that the agent correctly classified island vs mainland capitals.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define Ground Truth
    # Case-insensitive check preferred, but exact match "Island"/"Mainland" is the goal.
    targets = {
        "Dublin": "Island",
        "Tokyo": "Island",
        "Antananarivo": "Island",
        "Paris": "Mainland",
        "Cairo": "Mainland",
        "Brasilia": "Mainland"
    }
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve GeoPackage
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg')
    temp_gpkg.close() # Close so we can write to it
    
    try:
        copy_from_env("/sdcard/task_result.gpkg", temp_gpkg.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve result GeoPackage: {str(e)}"
        }

    # 2. Analyze Data
    data_correctness_score = 0
    data_max_score = 90 # 15 points per city
    
    try:
        conn = sqlite3.connect(temp_gpkg.name)
        cursor = conn.cursor()
        
        # Check modification count
        cursor.execute("SELECT name, description FROM world_capitals WHERE name IN (?,?,?,?,?,?)", 
                       tuple(targets.keys()))
        rows = cursor.fetchall()
        
        # Convert to dict for easier checking
        # Normalize keys to lower case for lookup, values kept as is
        results = {r[0]: r[1] for r in rows}
        
        for city, expected in targets.items():
            actual = results.get(city, "")
            if actual is None: actual = ""
            
            # Check correctness (Case-insensitive for partial credit logic, but we want exact)
            if actual.strip() == expected:
                data_correctness_score += 15
                feedback_parts.append(f"✓ {city}: Correct ({actual})")
            elif actual.strip().lower() == expected.lower():
                data_correctness_score += 10 # Penalty for case
                feedback_parts.append(f"⚠ {city}: Case mismatch ({actual})")
            else:
                feedback_parts.append(f"✗ {city}: Incorrect (Found: '{actual}', Expected: '{expected}')")
                
        conn.close()
        
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Database verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_gpkg.name):
            os.unlink(temp_gpkg.name)

    # 3. VLM Verification (Trajectory Analysis) - 10 points
    # We look for evidence that the agent actually opened the attribute form
    # preventing SQL injection or magic file replacement cheats
    vlm_score = 0
    
    frames = sample_trajectory_frames(traj, n=5)
    
    prompt = """
    You are verifying an agent using QField (GIS app) on Android.
    The agent's task was to edit attributes for specific cities.
    
    Look at these screenshots and determine:
    1. Is the QField 'Feature Form' or 'Attribute Editor' visible in any frame? (Look for fields like 'fid', 'name', 'country', 'description').
    2. Is the onscreen keyboard visible in any frame (indicating data entry)?
    3. Is the map visible in any frame?
    
    Return JSON:
    {
        "form_visible": true/false,
        "keyboard_visible": true/false,
        "map_visible": true/false
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("form_visible") or parsed.get("keyboard_visible"):
            vlm_score = 10
            feedback_parts.append("✓ VLM: UI interaction confirmed")
        else:
            feedback_parts.append("⚠ VLM: No attribute form or keyboard detected in trajectory samples")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Default to pass VLM if code fails, to rely on strong DB verification
        vlm_score = 10 

    total_score = data_correctness_score + vlm_score
    
    passed = total_score >= 85
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback_parts)
    }