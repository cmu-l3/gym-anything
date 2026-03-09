#!/usr/bin/env python3
"""
Verifier for river_border_crossings task.
Checks if the output shapefile exists, is a Point geometry, and contains features.
"""

import json
import os
import tempfile
import zipfile
import logging
import sys

# Ensure pyshp is available
try:
    import shapefile
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
    import shapefile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_river_border_crossings(traj, env_info, task_info):
    """
    Verify the river border crossings task.
    
    Criteria:
    1. Output shapefile exists (20 pts)
    2. File created during task (anti-gaming) (10 pts)
    3. Geometry type is Point or MultiPoint (CRITICAL) (40 pts)
       - If user intersects Line+Polygon, they get Lines (Wrong)
       - If user intersects Line+Line, they get Points (Correct)
    4. Feature count is reasonable (>5) (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    max_score = 100
    
    # 1. Get result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check existence
    if not result.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output shapefile not found at /home/ga/gvsig_data/exports/river_crossings.shp"
        }
    
    score += 20
    feedback_parts.append("File exists")

    # Check timestamp
    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File timestamp indicates pre-existence")

    # 2. Analyze Shapefile Geometry
    if not result.get("zip_available", False):
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | Failed to retrieve shapefile data"
        }

    temp_zip = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    extract_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env("/tmp/output_shapefile.zip", temp_zip.name)
        with zipfile.ZipFile(temp_zip.name, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
            
        # Find the .shp file in extracted dir
        shp_file = None
        for f in os.listdir(extract_dir):
            if f.endswith(".shp"):
                shp_file = os.path.join(extract_dir, f)
                break
        
        if not shp_file:
            return {"passed": False, "score": score, "feedback": "Corrupt zip data"}

        # Use pyshp to check geometry
        sf = shapefile.Reader(shp_file)
        geom_type = sf.shapeType
        num_features = len(sf)
        
        # pyshp shape types:
        # 1=Point, 3=PolyLine, 5=Polygon, 8=MultiPoint, 11=PointZ, 13=PolyLineZ, etc.
        # We accept Point (1), MultiPoint (8), PointZ (11), MultiPointZ (18), PointM (21), MultiPointM (28)
        
        point_types = [1, 8, 11, 18, 21, 28]
        line_types = [3, 13, 23]
        
        if geom_type in point_types:
            score += 40
            feedback_parts.append(f"Correct geometry type: Point/MultiPoint (Type {geom_type})")
            
            # Check count
            if num_features > 5:
                score += 30
                feedback_parts.append(f"Feature count good ({num_features} crossings found)")
            elif num_features > 0:
                score += 15
                feedback_parts.append(f"Feature count low ({num_features}), expected > 5")
            else:
                feedback_parts.append("Shapefile is empty")
                
        elif geom_type in line_types:
            feedback_parts.append(f"Incorrect geometry: LineString (Type {geom_type}). Did you clip/intersect lines with polygons? You must convert polygons to lines first.")
        else:
            feedback_parts.append(f"Incorrect geometry type: {geom_type}")

    except Exception as e:
        feedback_parts.append(f"Error analyzing shapefile: {str(e)}")
    finally:
        if os.path.exists(temp_zip.name):
            os.unlink(temp_zip.name)
        # Cleanup extract dir
        import shutil
        shutil.rmtree(extract_dir, ignore_errors=True)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }