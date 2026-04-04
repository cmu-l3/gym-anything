#!/usr/bin/env python3
"""
Verifier for topological_coloring_world_map task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_topological_coloring_world_map(traj, env_info, task_info):
    """
    Verify that the user performed topological coloring correctly.
    
    Criteria:
    1. GeoJSON output exists and is valid (10 pts)
    2. GeoJSON contains 'color_id' field (10 pts)
    3. GeoJSON created during task (anti-gaming) (10 pts)
    4. Adjacency Check: No neighbors share same color (40 pts)
       - Score scales with % of valid borders
    5. Project saved (10 pts)
    6. Symbology applied (Categorized on color_id) (20 pts)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    # Load result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    
    analysis = result.get("analysis", {})
    file_created = result.get("file_created_during_task", False)
    
    score = 0
    feedback_parts = []
    
    # 1. GeoJSON Exists (10)
    if analysis.get("geojson_exists") and analysis.get("geojson_valid"):
        score += 10
        feedback_parts.append("GeoJSON valid")
    else:
        feedback_parts.append("GeoJSON missing/invalid")
        
    # 2. Schema Check (10)
    if analysis.get("has_color_id"):
        score += 10
        feedback_parts.append("'color_id' field found")
    else:
        feedback_parts.append("Missing 'color_id' field")
        
    # 3. Timestamp (10)
    if file_created:
        score += 10
    else:
        feedback_parts.append("File not created during task")
        
    # 4. Adjacency (40)
    violations = analysis.get("adjacency_violations", 0)
    total_borders = analysis.get("total_borders_checked", 0)
    
    if total_borders > 0:
        if violations == 0:
            score += 40
            feedback_parts.append("Perfect topological coloring (0 violations)")
        else:
            # Partial credit?
            # 100% correct = 40 pts
            # 90% correct = 36 pts
            # Formula: 40 * (1 - violations/total)
            valid_ratio = 1.0 - (violations / total_borders)
            points = int(40 * valid_ratio)
            score += points
            feedback_parts.append(f"Adjacency issues: {violations} violations in {total_borders} borders")
    elif analysis.get("geojson_exists"):
        # If file exists but 0 borders checked, maybe single polygon or error?
        feedback_parts.append("No shared borders detected")
        
    # 5. Project Exists (10)
    if analysis.get("project_exists"):
        score += 10
        feedback_parts.append("Project saved")
    else:
        feedback_parts.append("Project missing")
        
    # 6. Symbology (20)
    renderer = analysis.get("project_renderer")
    attr = analysis.get("project_renderer_attr")
    
    if renderer == "categorizedSymbol" and attr == "color_id":
        score += 20
        feedback_parts.append("Categorized symbology applied correctly")
    elif renderer == "categorizedSymbol":
        score += 10
        feedback_parts.append(f"Categorized symbology on wrong field '{attr}'")
    else:
        feedback_parts.append("Symbology not categorized on color_id")
        
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }