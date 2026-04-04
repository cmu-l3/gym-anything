#!/usr/bin/env python3
"""
Verifier for QGIS Extract Vertices task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_extract_vertices(traj, env_info, task_info):
    """
    Verify the Extract Vertices task completion.
    
    Scoring Criteria (100 pts total):
    - CSV file exists: 10 pts
    - CSV is valid/parseable: 10 pts
    - Correct row count (8-12 rows acceptable): 20 pts
    - Has coordinate columns (X/Y or Lat/Lon): 15 pts
    - Coordinate values in expected geographic range: 15 pts
    - Has vertex index/ID field: 10 pts
    - File is newly created: 10 pts
    - Project file saved: 10 pts
    
    Pass Threshold: 55 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/extract_vertices_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. CSV Existence (10)
    if result.get("csv_exists"):
        score += 10
        feedback_parts.append("CSV file found")
    else:
        feedback_parts.append("CSV file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # 2. CSV Validity (10)
    if result.get("csv_valid"):
        score += 10
        feedback_parts.append("CSV is valid")
    else:
        feedback_parts.append("CSV is empty or invalid")
        
    # 3. Row Count (20)
    # 2 polygons * 5 vertices = 10 rows. 
    # QGIS might treat ring closure differently (4 or 5). Total 8-10 is perfect.
    # Allow 8-12 range for safety.
    rows = result.get("row_count", 0)
    if 8 <= rows <= 12:
        score += 20
        feedback_parts.append(f"Row count correct ({rows})")
    elif rows > 0:
        score += 5
        feedback_parts.append(f"Row count incorrect ({rows}, expected 8-10)")
    else:
        feedback_parts.append("No data rows")
        
    # 4. Coordinate Columns (15)
    if result.get("has_coord_columns"):
        score += 15
        feedback_parts.append(f"Coords found ({result.get('x_col_name')}, {result.get('y_col_name')})")
    else:
        feedback_parts.append("Missing X/Y coordinate columns")
        
    # 5. Coordinate Range (15)
    if result.get("coords_in_range"):
        score += 15
        feedback_parts.append("Coordinates in correct geographic range")
    elif result.get("has_coord_columns"):
        feedback_parts.append("Coordinates out of range (check CRS?)")
        
    # 6. Vertex Index (10)
    if result.get("has_vertex_index"):
        score += 10
        feedback_parts.append("Vertex index field present")
    else:
        feedback_parts.append("Missing vertex index field")
        
    # 7. File Newness (10)
    if result.get("file_is_new"):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates old file")
        
    # 8. Project File (10)
    if result.get("project_exists"):
        score += 10
        feedback_parts.append("Project saved")
    else:
        feedback_parts.append("Project file not saved")
        
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }