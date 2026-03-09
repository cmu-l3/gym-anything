#!/usr/bin/env python3
"""
Verifier for intersect_rivers_countries task.

Checks:
1. Output shapefile existence and creation time.
2. DBF structure: Must contain fields from both Rivers (Input) and Countries (Overlay).
3. DBF content: Must have > 0 records (non-empty intersection).
4. VLM verification of the workflow trajectory.
"""

import json
import os
import struct
import tempfile
import logging
from typing import Dict, Any, List, Tuple

# Import VLM utils from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"score": 0, "reasoning": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_dbf_header(dbf_path: str) -> Tuple[int, List[str]]:
    """
    Parses a DBF file to extract record count and field names.
    Returns (num_records, list_of_field_names).
    """
    try:
        with open(dbf_path, 'rb') as f:
            # DBF Header structure:
            # Byte 0: Version
            # Byte 1-3: Date
            # Byte 4-7: Number of records (uint32)
            # Byte 8-9: Header size (uint16)
            header_data = f.read(32)
            if len(header_data) < 32:
                return 0, []
            
            num_records = struct.unpack('<I', header_data[4:8])[0]
            header_size = struct.unpack('<H', header_data[8:10])[0]
            
            # Field descriptors start at byte 32. Each is 32 bytes.
            # Terminated by 0x0D.
            fields = []
            while f.tell() < header_size:
                field_data = f.read(32)
                if len(field_data) < 32:
                    break
                
                # Check for terminator
                if field_data[0] == 0x0D:
                    break
                    
                # Field name is first 11 bytes, null padded
                name_bytes = field_data[:11]
                name = name_bytes.split(b'\x00')[0].decode('ascii', errors='ignore').strip()
                if name:
                    fields.append(name)
                    
            return num_records, fields
    except Exception as e:
        logger.error(f"Error parsing DBF: {e}")
        return 0, []

def verify_intersect_rivers_countries(traj, env_info, task_info):
    """
    Verifies the intersection task result.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence & Timestamp (30 points)
    output_exists = result_data.get("output_exists", False)
    dbf_exists = result_data.get("dbf_exists", False)
    created_during_task = result_data.get("file_created_during_task", False)
    
    if output_exists and dbf_exists:
        score += 10
        feedback_parts.append("Output shapefile exists")
        
        if created_during_task:
            score += 20
            feedback_parts.append("File created during task session")
        else:
            feedback_parts.append("WARNING: File timestamp predates task start (anti-gaming fail)")
    else:
        feedback_parts.append("Output shapefile missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Analyze DBF Content (40 points)
    # We need to copy the DBF file from the container to analyze it
    output_base = result_data.get("output_base_path", "/home/ga/gvsig_data/exports/rivers_by_country")
    container_dbf_path = output_base + ".dbf"
    
    temp_dbf = tempfile.NamedTemporaryFile(delete=False, suffix='.dbf')
    temp_dbf.close() # Close so we can write to it via copy_from_env
    
    try:
        copy_from_env(container_dbf_path, temp_dbf.name)
        num_records, fields = parse_dbf_header(temp_dbf.name)
        
        # Check 3a: Non-empty result (20 points)
        if num_records > 0:
            score += 20
            feedback_parts.append(f"Result contains {num_records} features")
        else:
            feedback_parts.append("Result is empty (0 features)")

        # Check 3b: Attribute Schema (20 points)
        # We expect fields from Countries (e.g., ADMIN, POP_EST) and Rivers (e.g., name, scalerank)
        # Note: Shapefile field names are truncated to 10 chars
        fields_lower = [f.lower() for f in fields]
        
        # Keywords to look for
        country_keywords = ["admin", "pop_est", "gdp", "continent", "sov_a3"]
        river_keywords = ["scalerank", "rivernum", "featurecla"] # 'name' is ambiguous
        
        has_country_fields = any(any(k in f for k in country_keywords) for f in fields_lower)
        has_river_fields = any(any(k in f for k in river_keywords) for f in fields_lower)
        
        # Special check for 'name' which might appear twice or be renamed
        name_fields = [f for f in fields_lower if "name" in f]
        
        if has_country_fields and (has_river_fields or len(name_fields) >= 2):
            score += 20
            feedback_parts.append("Attributes from both layers detected")
        else:
            feedback_parts.append(f"Missing merged attributes. Fields found: {fields}")
            
    except Exception as e:
        feedback_parts.append(f"Failed to analyze DBF: {e}")
    finally:
        if os.path.exists(temp_dbf.name):
            os.unlink(temp_dbf.name)

    # 4. VLM Verification (30 points)
    # Use VLM to verify the workflow (Geoprocessing toolbox usage)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=8)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        if frames:
            prompt = """
            Review these screenshots of a user performing a GIS task in gvSIG Desktop.
            The user should be:
            1. Loading 'countries' and 'rivers' layers into a View.
            2. Opening the Geoprocessing Toolbox (SEXTANTE).
            3. Running the 'Intersection' tool.
            
            Look for:
            - A dialog box titled "Intersection" or similar.
            - A map view showing lines (rivers) and polygons (countries).
            - A final map where river lines might look different or a new layer is added.
            
            Did the user perform the Intersection geoprocess?
            Return JSON: {"performed_intersection": true/false, "confidence": 0-10}
            """
            
            vlm_result = query_vlm(frames, prompt)
            
            # Check implicit JSON parsing from the framework or parse manually if needed
            # Assuming query_vlm returns a dict or parsed JSON
            if isinstance(vlm_result, dict) and vlm_result.get("performed_intersection"):
                vlm_score = 30
                feedback_parts.append("VLM confirmed geoprocessing workflow")
            elif "true" in str(vlm_result).lower():
                vlm_score = 30
                feedback_parts.append("VLM confirmed workflow")
            else:
                feedback_parts.append("VLM could not verify geoprocessing workflow")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if programmatic score is high (>= 70), assume success to avoid false negatives due to VLM
        if score >= 70:
            vlm_score = 30
            feedback_parts.append("Programmatic verification strong; skipping VLM")

    score += vlm_score

    # Final Pass/Fail
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }