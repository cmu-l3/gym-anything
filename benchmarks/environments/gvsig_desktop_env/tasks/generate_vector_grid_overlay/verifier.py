#!/usr/bin/env python3
"""
Verifier for generate_vector_grid_overlay task.

Verifies:
1. Shapefile exists and was created during the task.
2. Geometry type is Polygon.
3. Feature count is within reasonable range for a 5x5 grid over Australia.
4. Grid cells are approximately 5x5 degrees (area ~25.0).
5. Grid extent covers Australia.
"""

import json
import os
import sys
import tempfile
import zipfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import pyshp (shapefile)
PYSHP_AVAILABLE = False
try:
    import shapefile
    PYSHP_AVAILABLE = True
except ImportError:
    logger.warning("pyshp not installed")

def ensure_dependencies():
    """Install pyshp if needed."""
    global PYSHP_AVAILABLE, shapefile
    if not PYSHP_AVAILABLE:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pyshp"])
            import shapefile as shp_module
            shapefile = shp_module
            PYSHP_AVAILABLE = True
        except Exception as e:
            logger.error(f"Failed to install pyshp: {e}")
            return False
    return True

def verify_generate_vector_grid_overlay(traj, env_info, task_info):
    """
    Verify the generated vector grid.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic Checks
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found at expected path."}
    
    score = 0
    feedback = []
    
    if result.get('created_during_task'):
        score += 15
        feedback.append("File created during task.")
    else:
        feedback.append("Warning: File timestamp indicates it wasn't created during this session.")

    if result.get('app_running'):
        score += 5
        feedback.append("gvSIG was running at end of task.")

    # 2. Analyze Shapefile
    if not result.get('zip_available'):
        return {"passed": False, "score": score, "feedback": " ".join(feedback) + " | Failed to retrieve shapefile data."}

    ensure_dependencies()
    if not PYSHP_AVAILABLE:
         return {"passed": False, "score": score, "feedback": " ".join(feedback) + " | Verifier dependency failure (pyshp)."}

    # Download and unzip shapefile
    temp_zip = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    extract_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env("/tmp/australia_grid.zip", temp_zip.name)
        with zipfile.ZipFile(temp_zip.name, 'r') as zf:
            zf.extractall(extract_dir)
            
        # Find the .shp file
        shp_files = [f for f in os.listdir(extract_dir) if f.endswith('.shp')]
        if not shp_files:
             return {"passed": False, "score": score, "feedback": " ".join(feedback) + " | Invalid zip content."}
        
        shp_path = os.path.join(extract_dir, shp_files[0])
        sf = shapefile.Reader(shp_path)
        
        # Criterion: Geometry Type (Polygon is 5)
        if sf.shapeType == 5:
            score += 20
            feedback.append("Geometry type is Polygon.")
        else:
            feedback.append(f"Wrong geometry type: {sf.shapeType} (Expected 5/Polygon).")

        # Criterion: Feature Count
        # Australia is approx 42 deg wide x 34 deg tall. 
        # 5 deg grid -> ~8.4 cols * ~6.8 rows ~= 57 cells.
        # Allow wide range for bounding box variations.
        count = len(sf.shapes())
        if 30 <= count <= 120:
            score += 20
            feedback.append(f"Feature count reasonable ({count}).")
        else:
            feedback.append(f"Feature count suspicious ({count}). Expected 30-120.")

        # Criterion: Cell Size / Area
        # 5x5 degrees = 25 square degrees.
        # Check median area of first 10 shapes
        shapes = sf.shapes()[:10]
        areas = []
        for shp in shapes:
            # Simple box area approximation (since it's a grid, bbox area == poly area usually)
            bbox = shp.bbox # [minx, miny, maxx, maxy]
            w = bbox[2] - bbox[0]
            h = bbox[3] - bbox[1]
            areas.append(w * h)
        
        # Check if approx 25
        avg_area = sum(areas) / len(areas) if areas else 0
        if 24.0 <= avg_area <= 26.0:
            score += 20
            feedback.append(f"Grid cell size approx 5x5 degrees (Area: {avg_area:.2f}).")
        else:
            feedback.append(f"Grid cell size incorrect (Avg Area: {avg_area:.2f}, expected ~25.0).")

        # Criterion: Spatial Extent
        # Must overlap Australia (Approx 112 to 155 E, -45 to -10 S)
        global_bbox = sf.bbox
        target_min_x, target_min_y, target_max_x, target_max_y = 112, -45, 154, -10
        
        # Check for overlap
        overlap_x = max(0, min(global_bbox[2], target_max_x) - max(global_bbox[0], target_min_x))
        overlap_y = max(0, min(global_bbox[3], target_max_y) - max(global_bbox[1], target_min_y))
        
        if overlap_x > 20 and overlap_y > 20: # Significant overlap
            score += 20
            feedback.append("Grid spatially covers Australia.")
        else:
            feedback.append(f"Grid does not cover Australia (BBox: {global_bbox}).")

    except Exception as e:
        feedback.append(f"Error analyzing shapefile: {str(e)}")
    finally:
        if os.path.exists(temp_zip.name):
            os.unlink(temp_zip.name)
        shutil.rmtree(extract_dir, ignore_errors=True)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }