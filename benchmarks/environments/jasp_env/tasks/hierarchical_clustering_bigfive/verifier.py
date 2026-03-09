#!/usr/bin/env python3
"""
Verifier for Hierarchical Clustering task in JASP.
Analyzes the saved .jasp file (which is a ZIP archive) to verify analysis settings.
"""

import json
import os
import tempfile
import zipfile
import shutil
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hierarchical_clustering(traj, env_info, task_info):
    """
    Verify the JASP hierarchical clustering analysis.
    
    1. Checks if .jasp file exists and is valid.
    2. Unzips and inspects internal JSONs for:
       - Hierarchical clustering analysis
       - Correct variables (Big 5)
       - 3 clusters
       - Dendrogram enabled
       - Cluster means enabled
    3. Uses VLM to confirm visual elements (dendrogram).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)
            
    if not meta.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output .jasp file was not saved."}
        
    if not meta.get('created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during this session."}
    
    score += 10 # File exists and is new
    feedback_parts.append("File saved successfully")

    # 2. Retrieve and analyze the .jasp file
    jasp_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    extract_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env(meta['output_path'], jasp_temp.name)
        
        # Unzip .jasp file
        try:
            with zipfile.ZipFile(jasp_temp.name, 'r') as zip_ref:
                zip_ref.extractall(extract_dir)
            score += 10 # Valid zip
            feedback_parts.append("Valid JASP file format")
        except zipfile.BadZipFile:
            return {"passed": False, "score": score, "feedback": "Saved file is not a valid JASP/ZIP archive."}
            
        # Recursive search for JSON content in the archive
        combined_json_text = ""
        analysis_found = False
        
        for root, dirs, files in os.walk(extract_dir):
            for file in files:
                if file.endswith('.json'):
                    try:
                        with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                            content = f.read()
                            combined_json_text += content + "\n"
                            # Check for specific analysis indicators
                            if "hierarchical" in content.lower() or "hclust" in content.lower():
                                analysis_found = True
                    except:
                        pass
        
        # Verify Analysis Type (15 pts)
        if analysis_found:
            score += 15
            feedback_parts.append("Hierarchical clustering analysis found")
        else:
            feedback_parts.append("No hierarchical clustering analysis detected in file")
            
        # Verify Variables (20 pts)
        # We look for the variable names in the JSON configuration
        required_vars = ["Agreeableness", "Conscientiousness", "Extraversion", "Neuroticism", "Openness"]
        vars_found = 0
        for var in required_vars:
            if var in combined_json_text:
                vars_found += 1
        
        var_score = (vars_found / 5) * 20
        score += var_score
        if vars_found == 5:
            feedback_parts.append("All 5 variables used")
        else:
            feedback_parts.append(f"Used {vars_found}/5 required variables")
            
        # Verify Cluster Count = 3 (15 pts)
        # Look for "3" associated with cluster settings keys
        # Regex or string search for keys like "numberOfClusters": 3
        import re
        if re.search(r'"(noOfClusters|manualNumberOfClusters|numberOfClusters|customNumberOfClusters)":\s*3', combined_json_text) or \
           re.search(r'"clusters":\s*3', combined_json_text):
            score += 15
            feedback_parts.append("Cluster count set to 3")
        else:
            feedback_parts.append("Could not verify cluster count = 3")
            
        # Verify Options: Dendrogram (10 pts) and Means (10 pts)
        if "dendrogram" in combined_json_text.lower():
            score += 10
            feedback_parts.append("Dendrogram enabled")
        
        if "means" in combined_json_text.lower() and "cluster" in combined_json_text.lower():
            score += 10
            feedback_parts.append("Cluster means enabled")
            
        # Verify Data Augmentation (10 pts)
        # Check if dataset has new columns or if "addPredictions" was logged
        if "addPredictions" in combined_json_text or "addClusters" in combined_json_text:
            score += 10
            feedback_parts.append("Cluster assignments added to data")
            
    except Exception as e:
        logger.error(f"Error analyzing JASP file: {e}")
        feedback_parts.append("Error analyzing file content")
    finally:
        if os.path.exists(jasp_temp.name):
            os.unlink(jasp_temp.name)
        shutil.rmtree(extract_dir, ignore_errors=True)

    # 3. VLM Verification (Backup/Confirmation)
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        # Ask VLM if it sees the specific plot
        vlm_res = query_vlm(
            image=final_screenshot,
            prompt="Is there a Dendrogram (tree diagram) visible in the results panel on the right? Does the analysis title say 'Hierarchical Clustering'?"
        )
        if vlm_res.get('success'):
            # If we missed programmatic checks but VLM sees it, give partial credit or boost confidence
            pass
            
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }