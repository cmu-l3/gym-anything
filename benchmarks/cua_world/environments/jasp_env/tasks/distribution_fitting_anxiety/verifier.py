#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_distribution_fitting(traj, env_info, task_info):
    """
    Verify that the JASP project file contains a Distribution Fit analysis
    comparing Normal and Gamma distributions for the Anxiety variable.
    """
    # 1. Setup and retrieve result metadata
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/JASP/Anxiety_Distributions.jasp')
    
    score = 0
    feedback_parts = []
    
    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Timestamp (Anti-gaming)
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output JASP file not found."}
    
    if not result_data.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task session."}

    score += 10 # File exists and is new
    feedback_parts.append("JASP file created.")

    # 3. Inspect JASP File Content
    # JASP files are ZIP archives. We need to extract the analysis definition.
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    analysis_found = False
    correct_variable = False
    correct_distributions = False
    
    try:
        copy_from_env(expected_path, temp_jasp.name)
        
        with zipfile.ZipFile(temp_jasp.name, 'r') as z:
            # Look for JSON files that might contain analysis settings
            # Common files: index.html (contains JSON in script tags), analysis-state.json, or similar.
            # In recent JASP versions, analysis parameters are often stored in 'embedded/...' or root JSONs.
            
            # Strategy: Search all text-readable files for specific key strings
            content_to_scan = ""
            for filename in z.namelist():
                if filename.endswith('.json') or filename.endswith('.html') or filename.endswith('.xml'):
                    try:
                        with z.open(filename) as f:
                            content_to_scan += f.read().decode('utf-8', errors='ignore')
                    except:
                        pass
            
            # Check for Module/Analysis Usage
            # The internal name for the module is often "jaspDistributions" or similar
            if "jaspDistributions" in content_to_scan or "ContinuousFit" in content_to_scan:
                analysis_found = True
                score += 30
                feedback_parts.append("Distributions module used.")
            else:
                feedback_parts.append("Distributions analysis not found in file.")

            # Check for Variable Assignment ('Anxiety')
            # Look for evidence that 'Anxiety' is associated with the analysis
            if "Anxiety" in content_to_scan:
                correct_variable = True
                score += 30
                feedback_parts.append("Anxiety variable found in project.")
            else:
                feedback_parts.append("Target variable 'Anxiety' not found in project.")

            # Check for Specific Distributions (Normal, Gamma)
            # Keys often look like "normal", "gamma" in the options list
            has_normal = "normal" in content_to_scan.lower() or "Normal" in content_to_scan
            has_gamma = "gamma" in content_to_scan.lower() or "Gamma" in content_to_scan
            
            if has_normal and has_gamma:
                correct_distributions = True
                score += 30
                feedback_parts.append("Both Normal and Gamma distributions selected.")
            elif has_normal or has_gamma:
                score += 15
                feedback_parts.append("Only one of Normal/Gamma distributions found.")
            else:
                feedback_parts.append("Required distributions (Normal, Gamma) not found.")

    except zipfile.BadZipFile:
        return {"passed": False, "score": 10, "feedback": "Created file is not a valid JASP archive."}
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Error parsing JASP file: {e}"}
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    # 4. Final Scoring
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }