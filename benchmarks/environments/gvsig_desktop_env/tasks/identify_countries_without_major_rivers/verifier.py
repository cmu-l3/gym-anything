#!/usr/bin/env python3
"""
Verifier for identify_countries_without_major_rivers task.

This script runs on the host machine. It copies the output shapefile from the
container and performs geospatial/attribute verification.

Success Criteria:
1. Output shapefile exists and was created during the task.
2. Contains expected "arid" countries (Saudi Arabia, Libya, etc.).
3. Does NOT contain "river" countries (Brazil, USA, etc.).
4. Feature count is reasonable (indicating correct spatial selection logic).
"""

import json
import os
import sys
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import pyshp, install if missing (standard for gym-anything verifiers)
try:
    import shapefile
except ImportError:
    import subprocess
    logger.info("Installing pyshp for verification...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
    import shapefile

def verify_identify_countries_without_major_rivers(traj, env_info, task_info):
    """
    Verify that the agent correctly identified countries without major rivers.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_countries = metadata.get('expected_countries', ["Saudi Arabia", "Libya", "Yemen", "Oman"])
    excluded_countries = metadata.get('excluded_countries', ["Brazil", "United States of America", "China"])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Create temp directory for analysis
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Retrieve result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
        
        # Check basic existence
        if not result_data.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "Output shapefile (arid_countries.shp) not found."}
        
        score += 10 # File exists
        
        if result_data.get('file_created_during_task', False):
            score += 10 # Created during task
        else:
            feedback_parts.append("Warning: Output file timestamp indicates it wasn't created during this session")
            
        # 2. Retrieve Shapefile components (.shp, .dbf, .shx)
        base_name = "arid_countries"
        files_retrieved = True
        for ext in ['.shp', '.dbf', '.shx']:
            remote_path = f"/home/ga/gvsig_data/exports/{base_name}{ext}"
            local_path = os.path.join(temp_dir, f"{base_name}{ext}")
            try:
                copy_from_env(remote_path, local_path)
            except Exception:
                files_retrieved = False
                feedback_parts.append(f"Missing component: {ext}")
        
        if not files_retrieved:
            return {
                "passed": False, 
                "score": score, 
                "feedback": "Incomplete shapefile components. " + " ".join(feedback_parts)
            }
            
        # 3. Analyze Shapefile Content
        try:
            sf = shapefile.Reader(os.path.join(temp_dir, base_name))
            
            # Get field names to find the 'NAME' or 'ADMIN' column
            fields = [f[0] for f in sf.fields[1:]] # Skip deletion flag
            
            name_idx = -1
            for i, f in enumerate(fields):
                if f.upper() in ['NAME', 'ADMIN', 'NAME_LONG']:
                    name_idx = i
                    break
            
            if name_idx == -1:
                return {
                    "passed": False,
                    "score": score,
                    "feedback": "Could not identify country name field in output shapefile."
                }
            
            # Collect all country names in the output
            output_countries = []
            for record in sf.records():
                output_countries.append(record[name_idx])
            
            # Logic Check 1: Inclusion (Arid countries should be present)
            present_expected = [c for c in expected_countries if c in output_countries]
            missing_expected = [c for c in expected_countries if c not in output_countries]
            
            # Logic Check 2: Exclusion (River countries should NOT be present)
            present_excluded = [c for c in excluded_countries if c in output_countries]
            
            # Logic Check 3: Count
            total_features = len(output_countries)
            
            # Scoring
            
            # A. Inclusion Score (30 pts)
            if len(expected_countries) > 0:
                inclusion_ratio = len(present_expected) / len(expected_countries)
                score += int(30 * inclusion_ratio)
                if inclusion_ratio < 1.0:
                    feedback_parts.append(f"Missing expected arid countries: {', '.join(missing_expected)}")
            
            # B. Exclusion Score (30 pts) - The most critical check for "Invert Selection"
            if len(present_excluded) == 0:
                score += 30
            else:
                # Heavy penalty if river countries are present (implies they didn't invert selection)
                feedback_parts.append(f"Incorrectly included river countries: {', '.join(present_excluded)}")
                # No points for exclusion if any major errors
            
            # C. Count Sanity (20 pts)
            # ~40-60 countries out of ~177 in Natural Earth 110m have no major rivers mapped
            if 20 <= total_features <= 80:
                score += 20
            else:
                feedback_parts.append(f"Suspicious feature count: {total_features} (Expected approx 20-80).")
                if total_features > 150:
                    feedback_parts.append("Likely selected ALL countries or failed to filter.")
                elif total_features < 5:
                    feedback_parts.append("Likely selected too few countries.")

        except Exception as e:
            return {
                "passed": False,
                "score": score,
                "feedback": f"Error parsing shapefile: {str(e)}"
            }

    finally:
        shutil.rmtree(temp_dir)

    # Final Pass Determination
    # Must have reasonably high score AND excluded the river countries
    passed = score >= 80 and len(present_excluded) == 0
    
    if passed:
        feedback_parts.append("Success: Correctly identified countries without major rivers.")
    else:
        feedback_parts.append("Task failed verification criteria.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }