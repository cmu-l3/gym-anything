#!/usr/bin/env python3
"""
Verifier for nasa_exoplanet_data_mining task.

SCORING CRITERIA (100 pts total):
1. NASA Archive Visited (10 pts)
2. JSON File Exists & Valid (10 pts)
3. 'Exoplanet Research' Bookmark Folder with Link (20 pts)
4. Data Completeness (20 pts) - Entries for all 4 targets
5. Data Accuracy (40 pts) - 10 pts per planet, checks ranges for Period, Radius, Temp

Pass threshold: 70 points (requires getting most data right, including the hidden Temp column).
"""

import json
import logging
import os
import tempfile
import base64

logger = logging.getLogger(__name__)

def verify_nasa_exoplanet_data_mining(traj, env_info, task_info):
    """Verify exoplanet data extraction accuracy and browser state."""
    
    # 1. Setup & Load Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    tmp_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback = []
    
    # 2. Check Browser History (10 pts)
    visits = result.get("archive_visits", 0)
    if visits > 0:
        score += 10
        feedback.append("Accessed NASA Exoplanet Archive (+10)")
    else:
        feedback.append("Did not visit NASA Exoplanet Archive (0/10)")

    # 3. Check Bookmarks (20 pts)
    if result.get("bookmark_folder_exists"):
        if result.get("archive_bookmark_exists", 0) > 0:
            score += 20
            feedback.append("Created bookmark folder with archive link (+20)")
        else:
            score += 10
            feedback.append("Created folder but missing specific link (+10)")
    else:
        feedback.append("Bookmark folder 'Exoplanet Research' not found (0/20)")

    # 4. Process Output File
    file_exists = result.get("file_exists")
    file_fresh = result.get("file_fresh")
    content_b64 = result.get("file_content_b64", "")
    
    user_data = {}
    json_valid = False
    
    if file_exists and file_fresh and content_b64:
        try:
            json_str = base64.b64decode(content_b64).decode('utf-8')
            user_data = json.loads(json_str)
            json_valid = True
            score += 10
            feedback.append("Valid JSON output file created (+10)")
        except Exception as e:
            feedback.append(f"Invalid JSON content: {str(e)[:50]} (0/10)")
    else:
        feedback.append("Output file missing or not created during task (0/10)")

    # 5. Data Accuracy Verification (60 pts total distributed)
    # 20 pts for completeness (4 planets present)
    # 40 pts for accuracy (values within range)
    
    targets = user_data.get("targets", {})
    ground_truth = task_info.get("metadata", {}).get("ground_truth", {})
    
    completeness_score = 0
    accuracy_score = 0
    
    for planet_name, gt in ground_truth.items():
        # Check if planet exists in user data (fuzzy match allowed for case/spacing)
        # We normalize keys to lowercase for matching
        user_planet_key = next((k for k in targets.keys() if planet_name.lower().replace(" ", "") in k.lower().replace(" ", "")), None)
        
        if not user_planet_key:
            feedback.append(f"Missing target: {planet_name}")
            continue
            
        completeness_score += 5  # 5 pts per planet presence
        planet_data = targets[user_planet_key]
        
        # Check Parameters
        p_score = 0
        
        # Period
        u_period = planet_data.get("period_days")
        if isinstance(u_period, (int, float)) and gt["period_range"][0] <= u_period <= gt["period_range"][1]:
            p_score += 2.5
            
        # Radius
        u_radius = planet_data.get("radius_earth_radii")
        if isinstance(u_radius, (int, float)) and gt["radius_range"][0] <= u_radius <= gt["radius_range"][1]:
            p_score += 2.5
            
        # Temp (Critical - requires finding hidden column)
        u_temp = planet_data.get("equilibrium_temp_k")
        if isinstance(u_temp, (int, float)) and gt["temp_range"][0] <= u_temp <= gt["temp_range"][1]:
            p_score += 3.0 # Slightly higher weight
        
        # Year
        u_year = planet_data.get("discovery_year")
        if u_year == gt["year"] or str(u_year) == str(gt["year"]):
            p_score += 2.0
            
        accuracy_score += p_score
        
        # Detailed feedback only if score is low for a planet
        if p_score < 10:
            feedback.append(f"{planet_name}: Partial match ({p_score}/10)")
            
    score += completeness_score
    score += min(40, accuracy_score) # Cap accuracy at 40 just in case
    
    feedback.append(f"Completeness Score: {completeness_score}/20")
    feedback.append(f"Accuracy Score: {accuracy_score:.1f}/40")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": "; ".join(feedback)
    }