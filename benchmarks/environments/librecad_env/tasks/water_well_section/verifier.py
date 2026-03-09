#!/usr/bin/env python3
"""
Verifier for LibreCAD Water Well Section task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_water_well_section(traj, env_info, task_info):
    """
    Verifies the water well cross-section drawing.
    
    Criteria:
    1. File creation/modification (Anti-gaming).
    2. DXF Validity and structure.
    3. Layer existence (GROUND, CASING, SCREEN, GRAVEL, WATER, PUMP, SEAL, DIMENSIONS, TEXT).
    4. Entity population (layers must contain geometry).
    5. Text content (Title and labels).
    6. Geometric bounds (Must extend deep enough).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. File Existence & Integrity (10 pts)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file water_well_section.dxf not found."}
    
    if not result.get('file_created_during_task', False):
        feedback_parts.append("WARNING: File timestamp predates task start.")
        # We don't fail immediately but penalty applies
    else:
        score += 5
        feedback_parts.append("File created during task.")

    dxf_data = result.get('dxf_analysis', {})
    if not dxf_data.get('valid_dxf', False):
        return {"passed": False, "score": score, "feedback": "File exists but is not a valid DXF."}
    
    score += 5 # Valid DXF
    
    # 2. Layer Verification (40 pts)
    # Required layers: GROUND, CASING, SCREEN, GRAVEL, WATER, PUMP, SEAL, DIMENSIONS, TEXT
    # (Allowing for case-insensitivity)
    required_layers = ["GROUND", "CASING", "SCREEN", "GRAVEL", "WATER", "PUMP", "SEAL", "DIMENSIONS", "TEXT"]
    existing_layers = [l.upper() for l in dxf_data.get('layers', [])]
    entity_counts = {k.upper(): v for k, v in dxf_data.get('entity_counts', {}).items()}
    
    found_layers = 0
    populated_layers = 0
    
    for req in required_layers:
        if req in existing_layers:
            found_layers += 1
            # Check if layer has entities
            if entity_counts.get(req, 0) > 0:
                populated_layers += 1
    
    # Score for creating layers
    layer_score = (found_layers / len(required_layers)) * 20
    score += layer_score
    feedback_parts.append(f"Layers found: {found_layers}/{len(required_layers)}")
    
    # Score for populating layers (drawing geometry on them)
    # We expect at least 7 layers to be populated for full points here
    if populated_layers >= 7:
        score += 20
        feedback_parts.append("Most layers populated with geometry.")
    elif populated_layers >= 4:
        score += 10
        feedback_parts.append("Some layers populated.")
    else:
        feedback_parts.append("Layers created but mostly empty.")
        
    # 3. Geometric Bounds Check (15 pts)
    # Well should extend to -150. Allow tolerance.
    bounds = dxf_data.get('bounds', {})
    min_y = bounds.get('min_y', 0)
    
    if min_y <= -140:
        score += 15
        feedback_parts.append(f"Depth correct (min Y: {min_y:.1f})")
    elif min_y <= -100:
        score += 8
        feedback_parts.append(f"Depth partial (min Y: {min_y:.1f}, expected -150)")
    else:
        feedback_parts.append(f"Drawing too shallow (min Y: {min_y:.1f})")
        
    # 4. Text Content Verification (25 pts)
    # Keywords: IRRIGATION, CASING, SCREEN, GRAVEL, SEAL, WATER, PUMP
    text_content = " ".join(dxf_data.get('text_content', [])).upper()
    keywords = ["IRRIGATION", "CASING", "SCREEN", "GRAVEL", "SEAL", "WATER", "PUMP"]
    found_keywords = 0
    
    for kw in keywords:
        if kw in text_content:
            found_keywords += 1
            
    if found_keywords >= 5:
        score += 25
        feedback_parts.append(f"Text labels good ({found_keywords}/{len(keywords)} found).")
    elif found_keywords >= 3:
        score += 15
        feedback_parts.append(f"Text labels partial ({found_keywords}/{len(keywords)} found).")
    else:
        feedback_parts.append("Missing most text labels.")
        
    # 5. Anti-gaming / Effort (10 pts)
    # Ensure it's not just a single layer dump
    if len(existing_layers) > 3 and result.get('output_size_bytes', 0) > 2000:
        score += 10
    
    # Normalize score
    score = min(score, 100)
    passed = score >= 60 and populated_layers >= 4
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }