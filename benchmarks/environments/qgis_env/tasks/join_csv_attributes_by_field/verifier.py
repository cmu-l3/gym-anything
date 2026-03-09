#!/usr/bin/env python3
"""
Verifier for join_csv_attributes_by_field task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_join_csv_attributes_by_field(traj, env_info, task_info):
    """
    Verify that the CSV attributes were correctly joined to the vector layer.
    
    Scoring Criteria:
    1. File Exists & Fresh (20 pts): Output GeoJSON exists and was created during task.
    2. Valid GeoJSON (10 pts): File parses correctly.
    3. Geometry Preserved (15 pts): Output contains Polygons (not just table).
    4. Joined Fields Present (20 pts): POP_EST and GDP_MD are present.
    5. Feature Count (15 pts): > 150 countries (verifies join didn't drop everything).
    6. Data Spot Checks (20 pts): USA and CHN population values are plausible.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
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
            
    analysis = result.get('analysis', {})
    score = 0
    feedback_parts = []
    
    # 1. File Exists & Fresh (20 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("New output file created")
    elif result.get('output_exists'):
        score += 10
        feedback_parts.append("Output file exists but timestamp check unclear")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Valid GeoJSON (10 pts)
    if analysis.get('valid_geojson'):
        score += 10
        feedback_parts.append("Valid GeoJSON")
    else:
        feedback_parts.append("Invalid GeoJSON format")
        
    # 3. Geometry Preserved (15 pts)
    if analysis.get('has_geometry'):
        score += 15
        feedback_parts.append("Geometry preserved (Polygons)")
    else:
        feedback_parts.append("Missing geometry (maybe exported as table?)")

    # 4. Joined Fields Present (20 pts)
    pop_found = analysis.get('pop_est_found', False)
    gdp_found = analysis.get('gdp_md_found', False)
    
    if pop_found and gdp_found:
        score += 20
        feedback_parts.append("Joined fields (POP_EST, GDP_MD) found")
    elif pop_found or gdp_found:
        score += 10
        feedback_parts.append("Partial joined fields found")
    else:
        feedback_parts.append("Joined fields MISSING")

    # 5. Feature Count (15 pts)
    count = analysis.get('feature_count', 0)
    # Natural Earth has ~177 countries. A correct join should have most of them.
    if count >= 150:
        score += 15
        feedback_parts.append(f"Feature count good ({count})")
    elif count > 0:
        score += 5
        feedback_parts.append(f"Feature count low ({count}, expected >150)")
    else:
        feedback_parts.append("No features in output")

    # 6. Data Spot Checks (20 pts)
    # USA Pop > 300M, China Pop > 1B
    usa_pop = analysis.get('usa_pop_check', 0)
    chn_pop = analysis.get('chn_pop_check', 0)
    
    data_correct = 0
    if usa_pop > 300000000: data_correct += 10
    if chn_pop > 1000000000: data_correct += 10
    
    score += data_correct
    if data_correct == 20:
        feedback_parts.append("Data values verified (USA, CHN)")
    elif data_correct > 0:
        feedback_parts.append("Partial data verification")
    else:
        feedback_parts.append("Data value check failed (values may be null/zero)")

    # Final Pass Logic
    # Pass if score >= 60 AND fields are present (critical part of task)
    passed = (score >= 60) and pop_found and gdp_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }