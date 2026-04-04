#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging
import math

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("verifier")

def install_dependencies():
    """Install required libraries if missing."""
    packages = []
    try:
        import shapefile
    except ImportError:
        packages.append("pyshp")
    
    try:
        import shapely
    except ImportError:
        packages.append("shapely")
        
    if packages:
        logger.info(f"Installing missing dependencies: {', '.join(packages)}")
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install"] + packages)

def verify_digitize_polygon_boundary(traj, env_info, task_info):
    """
    Verify the digitize_polygon_boundary task.
    
    Checks:
    1. File existence and creation time.
    2. Schema (Geometry type and fields).
    3. Attribute values.
    4. Spatial accuracy (Overlap with actual Iceland).
    """
    # ensure libs are present
    install_dependencies()
    import shapefile
    from shapely.geometry import shape, box, Polygon
    from shapely.validation import make_valid
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_attr_val = metadata.get('target_attribute_value', 'ISL-Zone-01')
    target_field = metadata.get('target_field_name', 'region_id')
    
    # Setup temporary directory for files
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Fetch Result JSON
        result_json_path = os.path.join(temp_dir, "result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data."}

        # Basic Checks
        if not result_data.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "The shapefile 'iceland_boundary.shp' was not found."}
        
        if not result_data.get("created_during_task", False):
            return {"passed": False, "score": 0, "feedback": "The shapefile exists but was not modified during the task."}

        # 2. Fetch Shapefiles (Agent and Reference)
        agent_shp_base = os.path.join(temp_dir, "agent_output")
        ref_shp_base = os.path.join(temp_dir, "reference")
        
        files_to_copy = [
            ("/tmp/agent_output.shp", agent_shp_base + ".shp"),
            ("/tmp/agent_output.shx", agent_shp_base + ".shx"),
            ("/tmp/agent_output.dbf", agent_shp_base + ".dbf"),
            ("/tmp/reference.shp", ref_shp_base + ".shp"),
            ("/tmp/reference.shx", ref_shp_base + ".shx"),
            ("/tmp/reference.dbf", ref_shp_base + ".dbf")
        ]
        
        for src, dst in files_to_copy:
            try:
                copy_from_env(src, dst)
            except Exception as e:
                logger.warning(f"Could not copy {src}: {e}")
                if "agent_output" in src:
                     return {"passed": False, "score": 10, "feedback": "Created shapefile seems corrupt or incomplete (missing .shx or .dbf)."}

        # 3. Analyze Agent Shapefile
        score = 20 # Points for creating file
        feedback = ["File created successfully."]
        
        try:
            sf_agent = shapefile.Reader(agent_shp_base)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to open created shapefile: {e}"}

        # Check Geometry Type
        # Type 5 is Polygon
        if sf_agent.shapeType != 5:
            feedback.append(f"Warning: Geometry type is {sf_agent.shapeType}, expected 5 (Polygon).")
            # We continue anyway if it's readable
        else:
            score += 10
            feedback.append("Correct geometry type (Polygon).")

        # Check Fields
        fields = [f[0] for f in sf_agent.fields[1:]] # Skip DeletionFlag
        if target_field not in fields:
            feedback.append(f"Missing required field '{target_field}'. Found: {fields}")
        else:
            score += 10
            feedback.append(f"Field '{target_field}' exists.")

        # Check Records
        if not sf_agent.records():
            return {"passed": False, "score": score, "feedback": "Shapefile is empty (no features drawn)."}
        
        record = sf_agent.record(0)
        record_dict = dict(zip(fields, record))
        val = record_dict.get(target_field, "")
        
        if val == target_attr_val:
            score += 20
            feedback.append(f"Attribute '{target_field}' correctly set to '{target_attr_val}'.")
        else:
            feedback.append(f"Attribute '{target_field}' mismatch. Expected '{target_attr_val}', got '{val}'.")

        # 4. Spatial Analysis
        try:
            # Read Reference Iceland Geometry
            sf_ref = shapefile.Reader(ref_shp_base)
            # Find Iceland (ISO_A3 = ISL or ADM0_A3 = ISL)
            # We iterate to find the index
            iceland_shape = None
            
            # Get field indices
            ref_fields = [f[0] for f in sf_ref.fields[1:]]
            try:
                iso_idx = ref_fields.index("ISO_A3")
            except ValueError:
                try:
                    iso_idx = ref_fields.index("ADM0_A3")
                except ValueError:
                    iso_idx = -1
            
            if iso_idx != -1:
                for i, rec in enumerate(sf_ref.records()):
                    if rec[iso_idx] == "ISL":
                        iceland_shape = shape(sf_ref.shape(i))
                        break
            
            if not iceland_shape:
                feedback.append("Verification Error: Could not locate Iceland in reference data.")
                # Fallback: Approximate bounding box for Iceland
                # bounds: (-24.5, 63.3, -13.5, 66.5)
                iceland_shape = box(-24.5, 63.3, -13.5, 66.5)

            # Get Agent Geometry
            agent_geom = shape(sf_agent.shape(0))
            if not agent_geom.is_valid:
                agent_geom = make_valid(agent_geom)
            
            # Calculate Overlap
            # Ideally: intersection area / iceland area approx 1
            # But the task says "rough boundary". 
            # So: Intersection should cover most of Iceland (high recall)
            # And Agent shape shouldn't be massive (precision)
            
            intersection = agent_geom.intersection(iceland_shape)
            
            iceland_area = iceland_shape.area
            intersection_area = intersection.area
            agent_area = agent_geom.area
            
            if iceland_area == 0:
                coverage = 0
            else:
                coverage = intersection_area / iceland_area
                
            # Precision: How much of the drawn shape is actually Iceland?
            # If they draw a box around the world, coverage is 100% but precision is 0.
            precision_ratio = agent_area / iceland_area if iceland_area > 0 else 999
            
            # Criteria:
            # 1. Coverage > 0.8 (Covers 80% of Iceland)
            # 2. Precision < 5 (Drawn shape is not more than 5x larger than Iceland)
            
            logger.info(f"Spatial Stats: Iceland Area={iceland_area}, Agent Area={agent_area}, Intersection={intersection_area}")
            logger.info(f"Coverage={coverage}, Size Ratio={precision_ratio}")

            if coverage > 0.8:
                score += 20
                feedback.append(f"Spatial: Good coverage of Iceland ({coverage:.1%}).")
                
                if precision_ratio < 5.0:
                    score += 20
                    feedback.append("Spatial: Boundary is reasonably tight.")
                else:
                    feedback.append(f"Spatial: Polygon is too large/loose (Size ratio: {precision_ratio:.1f}x).")
            else:
                feedback.append(f"Spatial: Polygon does not cover enough of Iceland (Coverage: {coverage:.1%}).")
                if precision_ratio > 100:
                    feedback.append("Spatial: Did you draw the shape in the wrong location?")

        except Exception as e:
            feedback.append(f"Spatial verification failed: {e}")
            import traceback
            traceback.print_exc()

        # Final Scoring
        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }
        
    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)