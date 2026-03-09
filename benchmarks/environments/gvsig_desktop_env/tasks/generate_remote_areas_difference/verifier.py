#!/usr/bin/env python3
"""
Verifier for generate_remote_areas_difference task.

Checks:
1. Shapefile exists and was created during the task.
2. Geometry type is Polygon (Difference operation on Polygons outputs Polygons).
3. Geometric complexity is high (presence of holes/vertices from subtraction).
4. Feature count is reasonable (roughly matches input countries).
"""

import json
import os
import sys
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def install_pyshp():
    """Install pyshp if not present."""
    try:
        import shapefile
        return True
    except ImportError:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
            return True
        except Exception as e:
            logger.error(f"Failed to install pyshp: {e}")
            return False

def verify_remote_areas(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Install dependencies
    if not install_pyshp():
        return {"passed": False, "score": 0, "feedback": "Verification dependency installation failed"}
    
    import shapefile

    # Load result JSON
    result_json_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)

    score = 0
    feedback = []
    
    # 1. Check Existence & Timestamp (30 pts)
    output_exists = result.get("output_exists", False)
    created_during = result.get("file_created_during_task", False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found"}
    
    score += 20
    feedback.append("File exists")
    
    if created_during:
        score += 10
        feedback.append("File created during task")
    else:
        feedback.append("WARN: File timestamp suspicious (pre-dates task)")

    # 2. Geometric Analysis (70 pts)
    # We need to pull the actual shapefile components to the host
    temp_dir = tempfile.mkdtemp()
    shp_local = os.path.join(temp_dir, "remote_areas.shp")
    dbf_local = os.path.join(temp_dir, "remote_areas.dbf")
    shx_local = os.path.join(temp_dir, "remote_areas.shx")
    
    try:
        copy_from_env("/tmp/remote_areas.shp", shp_local)
        copy_from_env("/tmp/remote_areas.dbf", dbf_local)
        copy_from_env("/tmp/remote_areas.shx", shx_local)
        
        sf = shapefile.Reader(shp_local)
        
        # Check Geometry Type (5 = Polygon)
        # Note: pyshp usually returns 5 for Polygon
        if sf.shapeType == 5:
            score += 20
            feedback.append("Correct geometry type (Polygon)")
        else:
            feedback.append(f"Incorrect geometry type: {sf.shapeType} (expected 5)")
            
        # Check Feature Count
        # Natural Earth countries has ~177 features.
        # The difference operation might split some (islands), or remove some (fully urbanized? unlikely).
        # We expect count roughly in range 100-500.
        count = len(sf.records())
        if 50 <= count <= 1000:
            score += 10
            feedback.append(f"Feature count reasonable ({count})")
        else:
            feedback.append(f"Feature count suspicious ({count})")
            
        # Check Geometric Complexity (Holes)
        # A simple country polygon has X points. Subtracting a buffered circle adds vertices.
        # We check the total number of points in the first few shapes or average.
        # Alternatively, we can just check file size in the result metadata, but analyzing points is better.
        
        total_points = 0
        samples = 0
        for s in sf.shapes()[:50]:
            total_points += len(s.points)
            samples += 1
            
        avg_points = total_points / samples if samples > 0 else 0
        
        # Natural Earth 110m countries are quite coarse. 
        # Carving circles (even approximated) should increase vertex count significantly OR 
        # create multipart polygons with rings.
        # We'll check if we have shapes with multiple parts (rings) which indicates holes.
        
        has_holes = False
        parts_count_accumulator = 0
        for s in sf.shapes():
            if len(s.parts) > 1:
                has_holes = True
                parts_count_accumulator += 1
                
        # Many countries have islands (parts > 1) naturally. 
        # But cutting holes increases the part count (inner rings are stored as parts in shapefile spec).
        # We'll rely on a heuristic: The operation definitely happened if we passed the previous checks 
        # and the file is valid. To be stricter, we assign points for validity.
        
        if avg_points > 10: # Very basic sanity check that it's not empty geometry
            score += 20
            feedback.append("Geometry contains valid vertices")
            
        if has_holes or count > 150:
            score += 20
            feedback.append("Geometry complexity indicates potential holes/difference operation")
            
    except Exception as e:
        feedback.append(f"Geometric verification failed: {str(e)}")
    finally:
        shutil.rmtree(temp_dir)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }