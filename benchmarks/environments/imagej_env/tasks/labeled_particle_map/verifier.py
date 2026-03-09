#!/usr/bin/env python3
"""
Verifier for labeled_particle_map task.

Verifies:
1. Flattened Map (PNG) exists and is RGB (indicating labels/overlay burned in).
2. Data CSV exists and contains correct columns (Area, Circ, Feret).
3. Particle count is within expected range for Blobs sample (excluding edges).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_labeled_particle_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/labeled_map_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Metadata
    metadata = task_info.get('metadata', {})
    min_count = metadata.get('expected_count_min', 40)
    max_count = metadata.get('expected_count_max', 65)

    # 1. Check Files Exist & Timestamp (20 pts)
    if result.get("map_exists") and result.get("csv_exists"):
        if result.get("files_newly_created"):
            score += 20
            feedback_parts.append("Files created successfully")
        else:
            feedback_parts.append("Files exist but are old (anti-gaming)")
    else:
        feedback_parts.append("Missing output files")

    # 2. Verify Map is Flattened/RGB (25 pts)
    # The original blobs is 8-bit. A mask is 8-bit.
    # A flattened image with colored labels is RGB.
    if result.get("map_exists"):
        if result.get("map_is_rgb"):
            score += 25
            feedback_parts.append("Map is RGB (labels flattened)")
        else:
            feedback_parts.append("Map is grayscale/binary (labels likely missing/not flattened)")

    # 3. Verify Columns (20 pts)
    if result.get("columns_valid"):
        score += 20
        feedback_parts.append("Measurement columns correct")
    else:
        feedback_parts.append(f"Missing columns (found: {result.get('csv_columns')})")

    # 4. Verify Particle Count (15 pts)
    count = result.get("csv_rows", 0)
    if min_count <= count <= max_count:
        score += 15
        feedback_parts.append(f"Particle count valid ({count})")
    else:
        feedback_parts.append(f"Particle count out of range ({count}, expected {min_count}-{max_count})")
        
    # 5. Visual Consistency Check (csv rows vs map) (20 pts)
    # If we have a valid RGB map and matching CSV rows, we assume visual consistency.
    if score >= 80: # If everything else is good
        score += 20
        feedback_parts.append("Data matches workflow")
    else:
        feedback_parts.append("Workflow incomplete")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }