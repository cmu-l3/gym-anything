#!/usr/bin/env python3
"""
Verifier for spatial_coverage_analysis task.

Criteria:
1. SDO_GEOMETRY columns created in both tables (5 pts)
2. Geometry data populated correctly (not NULL) (15 pts)
3. SRID is 4326 (WGS 84) (10 pts)
4. Tables registered in USER_SDO_GEOM_METADATA (10 pts)
5. Spatial Indexes created and VALID (10 pts)
6. Output file exists (5 pts)
7. Output content matches ground truth (unserviced sites) (35 pts)
   - Must not contain serviced sites (false positives)
   - Must contain unserviced sites (true positives)
8. Bonus/Robustness: Check for common errors (swapped lat/lon)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spatial_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = set(metadata.get('ground_truth_unserviced', []))
    
    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Database Structure & Data (40 pts total)
    if result.get("columns_created"):
        score += 5
        feedback_parts.append("Columns created")
    else:
        feedback_parts.append("GEO_LOCATION columns missing")

    if result.get("coordinates_populated"):
        score += 15
        feedback_parts.append("Geometry data populated")
    else:
        feedback_parts.append("Geometry data is NULL/empty")

    if result.get("srid_correct"):
        score += 10
        feedback_parts.append("SRID 4326 correct")
    else:
        feedback_parts.append("Incorrect SRID (must be 4326)")
        
    if result.get("metadata_registered"):
        score += 10
        feedback_parts.append("Metadata registered")
    else:
        feedback_parts.append("Missing USER_SDO_GEOM_METADATA entries")

    # Indexing (10 pts)
    if result.get("spatial_indexes_valid"):
        score += 10
        feedback_parts.append("Spatial indexes valid")
    elif result.get("spatial_indexes_exist"):
        score += 5
        feedback_parts.append("Spatial indexes exist but invalid")
    else:
        feedback_parts.append("No spatial indexes found")

    # Output Analysis (50 pts total)
    if result.get("output_file_exists"):
        score += 5
        feedback_parts.append("Output file found")
        
        # Analyze content
        agent_lines = result.get("output_lines", [])
        
        # Check for site names in lines
        # We do a substring match to be lenient on formatting (e.g., if they included ID or State)
        detected_sites = set()
        false_positives = 0
        
        # Known serviced sites that SHOULD NOT be there
        serviced_sites = [
            "Times Square", "Central Park", "Fenway Park", "Logan Airport", 
            "Independence Hall", "Pentagon", "Brooklyn Bridge", 
            "Jersey City", "Harvard Yard", "Greenwich Point"
        ]
        
        for line in agent_lines:
            # Check for correct hits
            for truth in ground_truth:
                if truth.lower() in line.lower():
                    detected_sites.add(truth)
            
            # Check for false positives
            for serviced in serviced_sites:
                if serviced.lower() in line.lower():
                    false_positives += 1

        true_positives = len(detected_sites)
        total_truth = len(ground_truth)
        
        # Scoring logic for content
        # 35 points allocated for accuracy
        if total_truth > 0:
            accuracy_score = (true_positives / total_truth) * 25
            score += accuracy_score
        
        # Penalty for false positives (max 10 points deduction from the 35 block, technically added bonus for cleanliness)
        cleanliness_score = 10
        if false_positives > 0:
            cleanliness_score = max(0, 10 - (false_positives * 2))
        score += cleanliness_score

        feedback_parts.append(f"identified {true_positives}/{total_truth} correct sites")
        if false_positives > 0:
            feedback_parts.append(f"included {false_positives} false positives")
            
    else:
        feedback_parts.append("Output file missing")

    return {
        "passed": score >= 60,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }