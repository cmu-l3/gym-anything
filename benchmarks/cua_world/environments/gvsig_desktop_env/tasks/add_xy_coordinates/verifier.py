#!/usr/bin/env python3
"""
Verifier for add_xy_coordinates task.
Checks if the output shapefile contains X_COORD and Y_COORD fields populated with correct values.
"""

import os
import sys
import json
import logging
import tempfile
import zipfile
import shutil
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Attempt to import pyshp, install if missing
try:
    import shapefile
except ImportError:
    import subprocess
    logger.info("Installing pyshp...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
    import shapefile

def verify_add_xy_coordinates(traj, env_info, task_info):
    """
    Verify the task output.
    
    Criteria:
    1. Output shapefile exists (15 pts)
    2. File created during task session (15 pts)
    3. X_COORD and Y_COORD fields exist (25 pts)
    4. Fields are numeric (Float/Double) (15 pts)
    5. Values match geometry coordinates (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve result JSON
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
            
    # Check basic file existence criteria
    if result.get("files_exist", False):
        score += 15
        feedback_parts.append("Output shapefile exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found"}

    if result.get("file_created_during_task", False):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't created in this session")

    # 2. Retrieve and Inspect Shapefile
    zip_path_in_container = result.get("zip_path", "")
    if not zip_path_in_container:
        return {"passed": False, "score": score, "feedback": "No zip path in result"}

    temp_zip = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    extract_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env(zip_path_in_container, temp_zip.name)
        
        with zipfile.ZipFile(temp_zip.name, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
            
        # Find the .shp file
        shp_file = None
        for f in os.listdir(extract_dir):
            if f.endswith(".shp"):
                shp_file = os.path.join(extract_dir, f)
                break
        
        if not shp_file:
            return {"passed": False, "score": score, "feedback": "Zip did not contain .shp file"}
            
        # 3. Analyze Shapefile Content
        sf = shapefile.Reader(shp_file)
        
        # Check Fields
        fields = [f[0].upper() for f in sf.fields[1:]] # Skip DeletionFlag
        field_types = {f[0].upper(): f[1] for f in sf.fields[1:]}
        
        has_x = "X_COORD" in fields
        has_y = "Y_COORD" in fields
        
        if has_x and has_y:
            score += 25
            feedback_parts.append("X_COORD and Y_COORD fields found")
        else:
            feedback_parts.append(f"Missing required fields. Found: {fields}")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
            
        # Check Field Types ('N' is numeric/int, 'F' is float)
        # In DBF, Float is often stored as Numeric with decimals
        x_type = field_types.get("X_COORD")
        y_type = field_types.get("Y_COORD")
        
        # Accept 'N' (Numeric) or 'F' (Float)
        if x_type in ['N', 'F'] and y_type in ['N', 'F']:
            score += 15
            feedback_parts.append("Fields are numeric type")
        else:
            feedback_parts.append(f"Incorrect field types (X:{x_type}, Y:{y_type}). Should be Numeric/Float.")
            
        # Check Values (Accuracy)
        records = sf.records()
        shapes = sf.shapes()
        
        total_checks = 0
        passed_checks = 0
        
        x_idx = fields.index("X_COORD")
        y_idx = fields.index("Y_COORD")
        
        # Check first 20 records
        for i in range(min(len(records), 20)):
            rec = records[i]
            shp = shapes[i]
            
            # Point geometry: [x, y]
            if len(shp.points) > 0:
                geo_x, geo_y = shp.points[0]
                
                try:
                    attr_x = float(rec[x_idx])
                    attr_y = float(rec[y_idx])
                    
                    # Tolerance (0.001 degrees is ~100m, sufficient for this task)
                    if math.isclose(geo_x, attr_x, abs_tol=0.001) and math.isclose(geo_y, attr_y, abs_tol=0.001):
                        passed_checks += 1
                    total_checks += 1
                except (ValueError, TypeError):
                    pass # Conversion failed
                    
        if total_checks > 0 and passed_checks == total_checks:
            score += 30
            feedback_parts.append("Coordinate values match geometry")
        elif total_checks > 0:
            feedback_parts.append(f"Coordinate values mismatch ({passed_checks}/{total_checks} correct)")
        else:
            feedback_parts.append("Could not verify values (empty file?)")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        feedback_parts.append(f"Verification error: {str(e)}")
    finally:
        if os.path.exists(temp_zip.name):
            os.unlink(temp_zip.name)
        if os.path.exists(extract_dir):
            shutil.rmtree(extract_dir)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }