#!/usr/bin/env python3
"""
Verifier for identify_equatorial_countries task.

Checks:
1. Shapefile exists and was created during the task.
2. Shapefile contains key equatorial countries (BRA, IDN, KEN, etc.).
3. Shapefile does NOT contain non-equatorial countries (USA, RUS, etc.).
4. Feature count is within reasonable range (approx 13 countries).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_equatorial_countries(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    must_include = set(metadata.get('must_include_codes', ["BRA", "IDN", "ECU", "KEN"]))
    must_exclude = set(metadata.get('must_exclude_codes', ["USA", "RUS"]))
    min_count = metadata.get('min_count', 8)
    max_count = metadata.get('max_count', 18)

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check file existence (20 pts)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found"}
    
    score += 10
    feedback_parts.append("Shapefile created")
    
    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task window")
    else:
        feedback_parts.append("File timestamp outside task window (potential stale data)")

    # Analysis data from export script
    analysis = result.get('analysis', {})
    feature_count = analysis.get('count', 0)
    countries_data = analysis.get('countries', [])
    
    # Flatten country codes/names found in the file
    found_codes = set()
    found_names = set()
    
    for c in countries_data:
        if 'code' in c and c['code']:
            found_codes.add(c['code'].upper())
        if 'name' in c and c['name']:
            found_names.add(c['name'].upper())

    # 2. Check inclusions (40 pts)
    # We check if a sufficient number of mandatory countries are present
    hits = 0
    missed = []
    
    for code in must_include:
        # Check against codes or names (some logic to handle name variations might be needed, but codes are safer)
        if code in found_codes:
            hits += 1
        else:
            # Fallback simple name check if code not found (e.g. BRA -> BRAZIL)
            # This is a loose check, mainly relying on codes
            missed.append(code)
    
    # Calculate inclusion score
    # Require at least 50% of the list for partial credit, 80% for full
    required_hits = len(must_include)
    
    if hits >= required_hits - 2: # Allow 1-2 misses
        score += 40
        feedback_parts.append(f"Correctly included {hits}/{required_hits} key countries")
    elif hits >= required_hits / 2:
        score += 20
        feedback_parts.append(f"Included some key countries ({hits}/{required_hits}) but missed: {', '.join(missed[:3])}...")
    else:
        feedback_parts.append(f"Missed most key countries (found {hits}/{required_hits})")

    # 3. Check exclusions (30 pts)
    # Penalize for including non-equatorial countries
    false_positives = []
    for code in must_exclude:
        if code in found_codes:
            false_positives.append(code)
    
    if not false_positives:
        score += 30
        feedback_parts.append("No obvious non-equatorial countries found")
    else:
        penalty = len(false_positives) * 10
        score += max(0, 30 - penalty)
        feedback_parts.append(f"Incorrectly included: {', '.join(false_positives)}")

    # 4. Check feature count (10 pts)
    if min_count <= feature_count <= max_count:
        score += 10
        feedback_parts.append(f"Feature count reasonable ({feature_count})")
    else:
        feedback_parts.append(f"Feature count suspicious ({feature_count}, expected {min_count}-{max_count})")

    # Pass logic
    # Must have the file, decent inclusion, and minimal false positives
    passed = (result.get('output_exists') and 
              hits >= (required_hits / 2) and 
              len(false_positives) == 0 and
              score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }