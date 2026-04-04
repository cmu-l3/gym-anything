#!/usr/bin/env python3
"""
Verifier for JASP PCA Task.
Verifies that a .jasp file exists, is a valid zip, and contains a configured PCA analysis.
"""

import json
import os
import tempfile
import zipfile
import logging
import shutil
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pca_big_five(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the PCA task by inspecting the saved JASP file.
    
    JASP files are ZIP archives containing 'analyses.json' which details the
    configured analyses.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {}).get('grading', {})
    expected_path = task_info.get('metadata', {}).get('expected_output_path')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Create a temporary directory for extraction
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Retrieve the Result JSON from the container
        task_result_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", task_result_path)
            with open(task_result_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {str(e)}"}
        
        # 2. Verify File Existence and Timestamp (Anti-gaming)
        if not result_data.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Output JASP file not found."}
        
        score += metadata.get("file_exists", 10)
        feedback_parts.append("File exists.")

        if not result_data.get("file_created_during_task", False):
            return {"passed": False, "score": 0, "feedback": "File exists but was not created during this task session (anti-gaming check failed)."}
        
        # 3. Retrieve and Unzip the JASP file
        local_jasp_path = os.path.join(temp_dir, "analysis.jasp")
        try:
            copy_from_env(expected_path, local_jasp_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to copy JASP file for inspection: {str(e)}"}
            
        if not zipfile.is_zipfile(local_jasp_path):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid JASP archive (corrupted or empty)."}
            
        score += metadata.get("valid_zip", 10)
        feedback_parts.append("Valid JASP archive.")
        
        # Extract analyses.json
        try:
            with zipfile.ZipFile(local_jasp_path, 'r') as z:
                # JASP structure usually has 'analyses.json' at root or nested
                # We'll look for it
                file_list = z.namelist()
                if "analyses.json" not in file_list:
                    # Fallback search
                    analyses_files = [f for f in file_list if f.endswith("analyses.json")]
                    if not analyses_files:
                        return {"passed": False, "score": score, "feedback": "Invalid JASP file: analyses.json not found."}
                    analyses_path = analyses_files[0]
                else:
                    analyses_path = "analyses.json"
                
                with z.open(analyses_path) as f:
                    analyses_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse JASP analysis data: {str(e)}"}

        # 4. Verify Analysis Configuration
        # analyses_data is typically a list of analysis objects or a dict with an 'results' list
        # We need to find the PCA
        
        analyses_list = []
        if isinstance(analyses_data, list):
            analyses_list = analyses_data
        elif isinstance(analyses_data, dict):
            # Try specific JASP keys
            if "analyses" in analyses_data:
                analyses_list = analyses_data["analyses"]
            elif "results" in analyses_data:
                analyses_list = analyses_data["results"]
            else:
                analyses_list = [analyses_data] # Maybe it's just one object

        pca_analysis = None
        for analysis in analyses_list:
            # Check name or title
            name = analysis.get("name", "").lower()
            title = analysis.get("title", "").lower()
            options = analysis.get("options", {})
            
            # Identify PCA
            if "principal component" in title or "pca" in name or "principalcomponent" in name:
                pca_analysis = analysis
                break
            
            # Sometimes JASP just calls it 'Factor Analysis' with a specific option
            if "factor" in title or "factor" in name:
                # Check options for PCA specific settings? 
                # Usually PCA is distinct in the name structure, but let's be safe
                pass

        if not pca_analysis:
             return {"passed": False, "score": score, "feedback": "No Principal Component Analysis (PCA) found in the file."}

        score += metadata.get("pca_analysis_found", 15)
        feedback_parts.append("PCA analysis found.")
        
        opts = pca_analysis.get("options", {})
        
        # Check Variables (at least 3 of 5 for partial, all 5 for full)
        # Options structure varies by version, but usually "variables" key exists
        vars_assigned = opts.get("variables", [])
        # If vars_assigned is empty, check "variablesForm" or similar
        
        # Convert all assigned vars to lowercase for comparison
        vars_lower = [str(v).lower() for v in vars_assigned]
        expected_vars = ["agreeableness", "conscientiousness", "extraversion", "neuroticism", "openness"]
        
        # Count matches
        match_count = sum(1 for v in expected_vars if any(v in assigned for assigned in vars_lower))
        
        if match_count == 5:
            score += metadata.get("variables_correct", 20)
            feedback_parts.append("All variables assigned.")
        elif match_count >= 3:
            score += metadata.get("variables_correct", 20) // 2
            feedback_parts.append(f"Partial variables assigned ({match_count}/5).")
        else:
            feedback_parts.append(f"Incorrect variables assigned (found {match_count}/5).")

        # Check Rotation (Varimax)
        rotation = str(opts.get("rotation", "")).lower()
        if "varimax" in rotation:
            score += metadata.get("rotation_varimax", 15)
            feedback_parts.append("Varimax rotation configured.")
        else:
            feedback_parts.append(f"Rotation incorrect (found: {rotation}).")

        # Check Scree Plot
        # JASP boolean options are often just keys in the options dict
        scree = opts.get("screePlot", False)
        if scree:
            score += metadata.get("scree_plot", 15)
            feedback_parts.append("Scree plot enabled.")
        else:
            feedback_parts.append("Scree plot NOT enabled.")

        # Check Path Diagram
        path_diag = opts.get("pathDiagram", False)
        if path_diag:
            score += metadata.get("path_diagram", 15)
            feedback_parts.append("Path diagram enabled.")
        else:
            feedback_parts.append("Path diagram NOT enabled.")

        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)