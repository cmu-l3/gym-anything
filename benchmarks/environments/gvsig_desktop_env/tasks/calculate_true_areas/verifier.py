#!/usr/bin/env python3
"""
Verifier for calculate_true_areas task.

Verifies:
1. Shapefile creation (existence, valid format)
2. Projection correctness (via .prj analysis or area magnitude)
3. Calculation accuracy (checks specific country areas against ground truth)
4. Unit correctness (Square Kilometers vs Meters vs Degrees)
"""

import json
import os
import sys
import tempfile
import zipfile
import logging
import shutil
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Try to import pyshp for shapefile reading
try:
    import shapefile
    SHAPEFILE_LIB_AVAILABLE = True
except ImportError:
    # If not available, we will try to install it or fail gracefully
    SHAPEFILE_LIB_AVAILABLE = False


def ensure_dependencies():
    """Ensure required packages are available."""
    global SHAPEFILE_LIB_AVAILABLE, shapefile
    if not SHAPEFILE_LIB_AVAILABLE:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pyshp"])
            import shapefile as shp_module
            shapefile = shp_module
            SHAPEFILE_LIB_AVAILABLE = True
        except Exception as e:
            logger.error(f"Failed to install pyshp: {e}")
            return False
    return True


def verify_calculate_true_areas(traj, env_info, task_info):
    """
    Verify the calculate_true_areas task.
    """
    # 0. Check dependencies and setup
    if not ensure_dependencies():
        return {"passed": False, "score": 0, "feedback": "Verification failed: Could not install required libraries (pyshp)."}

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: Copy function not available."}

    metadata = task_info.get('metadata', {})
    expected_brazil = metadata.get('brazil_area_sqkm_approx', 8515767)
    expected_greenland = metadata.get('greenland_area_sqkm_approx', 2166086)
    tolerance_percent = metadata.get('tolerance_percent', 15)

    score = 0
    feedback_parts = []
    
    # Create temp directory for artifacts
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Get the result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result metadata: {str(e)}"}

        if not result_data.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Task Failed: Output shapefile was not created."}

        score += 10 # File exists
        feedback_parts.append("Output file exists.")

        if result_data.get("file_created_during_task", False):
            score += 10 # Created during task
            feedback_parts.append("File created during task session.")
        else:
            feedback_parts.append("Warning: File timestamp suggests it wasn't created in this session.")

        # 2. Get and unzip the shapefile
        zip_remote_path = result_data.get("zip_path")
        if not zip_remote_path:
            return {"passed": False, "score": score, "feedback": " ".join(feedback_parts) + " (Zip not found)"}

        zip_local_path = os.path.join(temp_dir, "result.zip")
        try:
            copy_from_env(zip_remote_path, zip_local_path)
            with zipfile.ZipFile(zip_local_path, 'r') as zip_ref:
                zip_ref.extractall(temp_dir)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": " ".join(feedback_parts) + f" Failed to retrieve/extract shapefile: {str(e)}"}

        # 3. Analyze Shapefile Content
        shp_files = [f for f in os.listdir(temp_dir) if f.endswith(".shp")]
        if not shp_files:
            return {"passed": False, "score": score, "feedback": " ".join(feedback_parts) + " No .shp file found in archive."}
        
        shp_path = os.path.join(temp_dir, shp_files[0])
        
        try:
            sf = shapefile.Reader(shp_path)
            fields = [f[0] for f in sf.fields[1:]] # Skip deletion flag
            records = sf.records()
            
            # Check for Area field
            area_field_name = None
            for f in fields:
                if "AREA" in f.upper() or "KM2" in f.upper():
                    area_field_name = f
                    break
            
            if not area_field_name:
                return {
                    "passed": False, 
                    "score": score, 
                    "feedback": " ".join(feedback_parts) + f" Failed: No field named 'AREA' or similar found. Fields: {fields}"
                }
            
            score += 20 # Field added
            feedback_parts.append(f"Found area field: {area_field_name}.")
            
            # Find Brazil and Greenland indices
            # Natural Earth usually has 'NAME' or 'ADMIN'
            name_idx = -1
            for i, f in enumerate(fields):
                if f.upper() in ['NAME', 'ADMIN', 'NAME_LONG']:
                    name_idx = i
                    break
            
            if name_idx == -1:
                # Fallback: assume first string field
                name_idx = 0 

            area_idx = fields.index(area_field_name)
            
            brazil_val = None
            greenland_val = None
            
            for r in records:
                country_name = str(r[name_idx])
                if "Brazil" in country_name:
                    brazil_val = r[area_idx]
                if "Greenland" in country_name:
                    greenland_val = r[area_idx]
            
            if brazil_val is None:
                 feedback_parts.append("Could not find Brazil in records to verify area.")
            else:
                # 4. Check Values
                # Expected Brazil: ~8.5 million
                # Tolerance
                lower_bound = expected_brazil * (1 - tolerance_percent/100)
                upper_bound = expected_brazil * (1 + tolerance_percent/100)
                
                # Check for Unit Errors
                if brazil_val < 1000:
                    feedback_parts.append(f"Brazil area ({brazil_val:.2f}) looks like Degrees (WGS84). Projection or calculation error.")
                elif brazil_val > 8000000000:
                    feedback_parts.append(f"Brazil area ({brazil_val:.2e}) looks like Square Meters. Forgot to convert to SQ KM.")
                elif lower_bound <= brazil_val <= upper_bound:
                    score += 30 # Value Correct
                    feedback_parts.append(f"Brazil area correct ({brazil_val:,.0f} km²).")
                else:
                    feedback_parts.append(f"Brazil area ({brazil_val:,.0f}) is outside tolerance ({expected_brazil:,.0f}).")

                # 5. Check Projection (via Greenland)
                # Mercator distorts Greenland to be almost size of Africa (~30M km^2)
                # Equal Area should be ~2.1M km^2
                if greenland_val:
                    if greenland_val > 6000000:
                        feedback_parts.append(f"Greenland area is huge ({greenland_val:,.0f} km²). Likely used Mercator/Non-Equal-Area projection.")
                    elif 1500000 <= greenland_val <= 3000000:
                        score += 30 # Projection Correct
                        feedback_parts.append("Projection likely Equal-Area (Greenland size normal).")
                    else:
                        feedback_parts.append(f"Greenland area {greenland_val:,.0f} unexpected.")

        except Exception as e:
            return {"passed": False, "score": score, "feedback": " ".join(feedback_parts) + f" Error reading shapefile: {str(e)}"}

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }