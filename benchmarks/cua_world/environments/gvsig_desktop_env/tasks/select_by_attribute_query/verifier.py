#!/usr/bin/env python3
"""
Verifier for select_by_attribute_query task.

Checks:
1. Output file exists and was created during the task.
2. Content analysis:
   - Contains header count line.
   - Contains major economies (USA, China, etc.).
   - Does NOT contain small economies (checking correct query logic).
   - Count is within reasonable range (10-30).
3. VLM Verification:
   - Checks trajectory for query dialog interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_select_by_attribute_query(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    must_contain = metadata.get('must_contain', ["United States", "China"])
    must_not_contain = metadata.get('must_not_contain', ["Fiji", "Chad"])
    min_count = metadata.get('min_count', 10)
    max_count = metadata.get('max_count', 30)

    # 1. Load Task Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check File Existence & Timestamp
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    if not result_data.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during this task session (stale data)."}

    # 3. Analyze Text Content
    score = 20  # Base points for file existing
    feedback = ["File created successfully."]
    passed_content_check = False
    
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        # The export script copies the user file to /tmp/high_gdp_countries_export.txt
        copy_from_env("/tmp/high_gdp_countries_export.txt", temp_txt.name)
        with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            lines = [l.strip() for l in content.splitlines() if l.strip()]
    except Exception as e:
        return {"passed": False, "score": 20, "feedback": f"File exists but could not be read: {str(e)}"}
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    if not lines:
        return {"passed": False, "score": 20, "feedback": "Output file is empty."}

    # Verify Count
    count_line_found = False
    try:
        # Check first line for "Count:"
        if "Count:" in lines[0]:
            count_val = int(lines[0].split(":")[1].strip())
            count_line_found = True
            if min_count <= count_val <= max_count:
                score += 10
                feedback.append(f"Count {count_val} is within expected range.")
            else:
                feedback.append(f"Count {count_val} is outside expected range ({min_count}-{max_count}).")
        else:
            feedback.append("First line does not match format 'Count: [number]'.")
    except:
        feedback.append("Could not parse count line.")

    # Verify Countries
    found_countries = 0
    missing_countries = []
    content_lower = content.lower()
    
    for country in must_contain:
        if country.lower() in content_lower:
            found_countries += 1
        else:
            missing_countries.append(country)

    if found_countries == len(must_contain):
        score += 30
        feedback.append("All expected major economies found.")
    elif found_countries > 0:
        score += (30 * (found_countries / len(must_contain)))
        feedback.append(f"Found {found_countries}/{len(must_contain)} expected countries. Missing: {', '.join(missing_countries)}")
    else:
        feedback.append("No expected major economies found in the list.")

    # Verify Negative Constraints (Anti-gaming / Correct Query Logic)
    found_bad = []
    for country in must_not_contain:
        if country.lower() in content_lower:
            found_bad.append(country)
    
    if not found_bad:
        score += 20
        feedback.append("Query logic seems correct (no low-GDP countries found).")
        passed_content_check = True
    else:
        score -= 10
        feedback.append(f"Found unexpected low-GDP countries: {', '.join(found_bad)}. Query threshold likely incorrect.")

    # 4. VLM Trajectory Verification
    # We want to see the Query/Selection dialog or the Expression builder
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Analyze these screenshots of a GIS workflow.\n"
            "The user should be performing a 'Select by Attributes' query.\n"
            "Look for:\n"
            "1. A dialog box titled 'Selection by attributes', 'Query', or similar.\n"
            "2. An expression like 'GDP_MD_EST > 1000000'.\n"
            "3. The map showing specific countries highlighted (yellow/colored selection).\n"
            "Did the user perform these actions?"
        )
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt).lower()
            if "yes" in vlm_result or "select" in vlm_result or "query" in vlm_result:
                score += 20
                feedback.append("VLM confirms query workflow.")
            else:
                feedback.append("VLM could not clearly verify query dialog usage.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Do not penalize score for VLM infrastructure failure, give benefit of doubt if file is good
            if passed_content_check:
                score += 20

    # Final Score Calculation
    passed = (score >= 70) and passed_content_check and (found_countries >= 2)
    
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " ".join(feedback)
    }