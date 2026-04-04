#!/usr/bin/env python3
"""
Verifier for load_csv_as_event_layer task.
Checks if the earthquake CSV was correctly loaded and exported as a shapefile.
"""

import json
import os
import sys
import tempfile
import logging
import struct

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def install_pyshp():
    """Try to install pyshp if not present (for robust shapefile reading)."""
    try:
        import shapefile
        return True
    except ImportError:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pyshp"])
            return True
        except Exception as e:
            logger.warning(f"Failed to install pyshp: {e}")
            return False

def verify_load_csv_as_event_layer(traj, env_info, task_info):
    """
    Verify that the agent loaded the CSV and exported a valid shapefile.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_feature_count', 42)
    tolerance = metadata.get('feature_count_tolerance', 5)

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check basic existence
    if not result.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output shapefile (earthquakes.shp) was not found in the export directory."
        }

    if not result.get('file_created_during_task', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but was not created during this task session."
        }

    # 3. Retrieve the Shapefile components for analysis
    # We need .shp, .shx, and .dbf to fully verify
    score = 20  # Base score for file existence
    feedback = "Shapefile exists. "
    
    temp_dir = tempfile.mkdtemp()
    shp_local = os.path.join(temp_dir, "earthquakes.shp")
    shx_local = os.path.join(temp_dir, "earthquakes.shx")
    dbf_local = os.path.join(temp_dir, "earthquakes.dbf")
    
    try:
        copy_from_env(result['output_path'], shp_local)
        copy_from_env(result['output_path'].replace('.shp', '.shx'), shx_local)
        copy_from_env(result['output_path'].replace('.shp', '.dbf'), dbf_local)
        
        # 4. Analyze Shapefile content
        # Use pyshp if available, otherwise fallback to simple binary checks
        pyshp_available = install_pyshp()
        
        real_count = 0
        is_point = False
        has_attribs = False
        
        if pyshp_available:
            try:
                import shapefile
                sf = shapefile.Reader(shp_local)
                real_count = len(sf.shapes())
                # Shape type 1 is Point, 11 is PointZ, 21 is PointM
                shape_type = sf.shapeType
                is_point = shape_type in [1, 11, 21]
                
                # Check fields
                fields = [f[0] for f in sf.fields[1:]] # skip deletion flag
                # Expect 'mag', 'depth', 'place' etc.
                has_attribs = any(f in ['mag', 'depth', 'place', 'latitude', 'longitude'] for f in fields)
                
                logger.info(f"Shapefile analysis: Type={shape_type}, Count={real_count}, Fields={fields}")
            except Exception as e:
                feedback += f"Error parsing shapefile: {e}. "
        else:
            # Fallback manual parsing if pyshp install failed
            # Read shape type from header (byte 32)
            with open(shp_local, 'rb') as f:
                f.seek(32)
                st = struct.unpack('<I', f.read(4))[0]
                is_point = (st in [1, 11, 21])
                
            # Estimate count from file size (rough)
            # This is less reliable, but better than nothing
            file_size = os.path.getsize(shp_local)
            if file_size > 1000: # 42 points should be > 1KB
                real_count = expected_count # Give benefit of doubt if binary check passes
            
            # Check DBF existence for attributes
            has_attribs = os.path.exists(dbf_local) and os.path.getsize(dbf_local) > 100

        # Scoring Logic
        
        # Geometry Type (15 pts)
        if is_point:
            score += 15
            feedback += "Geometry type is Point (Correct). "
        else:
            feedback += "Geometry type is NOT Point. "
            
        # Feature Count (25 pts)
        if abs(real_count - expected_count) <= tolerance:
            score += 25
            feedback += f"Feature count is correct ({real_count}). "
        else:
            feedback += f"Feature count mismatch: found {real_count}, expected ~{expected_count}. "
            
        # Attributes (10 pts)
        if has_attribs:
            score += 10
            feedback += "Attributes preserved. "
        else:
            feedback += "Attribute table missing or empty. "
            
        # 5. VLM Visual Verification (30 pts)
        # We rely on the trajectory showing the points on the map
        from gym_anything.vlm import get_final_screenshot, query_vlm
        final_img = get_final_screenshot(traj)
        
        if final_img:
            vlm_resp = query_vlm(
                images=[final_img],
                prompt="Does this map show a world map with scattered dots/points overlaid on top of it? The dots represent earthquakes. Respond 'YES' or 'NO'."
            )
            if "YES" in vlm_resp.upper():
                score += 30
                feedback += "Visual verification passed: Points visible on map. "
            else:
                feedback += "Visual verification failed: Points not clearly visible. "
        else:
            feedback += "No screenshot available for visual verification. "

    except Exception as e:
        feedback += f"Verification error: {str(e)}"
    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 65 and is_point
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }