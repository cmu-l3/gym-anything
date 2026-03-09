#!/usr/bin/env python3
"""
Verifier for JASP K-Means Clustering Task.

Verifies:
1. .jasp output file exists and is a valid ZIP.
2. Contains K-Means Clustering analysis.
3. Correct variables (Big 5 traits) used.
4. Correct cluster count (3).
5. "Add predicted clusters to data" enabled (column added).
6. "Cluster means" plot enabled.
"""

import json
import zipfile
import tempfile
import os
import shutil
import logging
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_kmeans_clustering(traj, env_info, task_info):
    """
    Verify JASP K-Means clustering task execution.
    """
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_file_path', '/home/ga/Documents/JASP/BigFive_KMeans.jasp')
    
    score = 0
    max_score = 100
    feedback = []
    
    # Temporary directory for processing
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        jasp_file_path = os.path.join(temp_dir, "analysis.jasp")
        
        # 2. Retrieve Task Result Metadata
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result metadata: {str(e)}"}

        # 3. Check File Existence and Creation
        if not task_result.get("file_exists", False):
            return {"passed": False, "score": 0, "feedback": "Output file BigFive_KMeans.jasp was not saved."}
        
        score += 10
        feedback.append("File created successfully.")

        if not task_result.get("file_created_during_task", False):
            feedback.append("Warning: File timestamp indicates it might be old.")
        else:
            score += 10
            feedback.append("File created during task session.")

        # 4. Retrieve and Unpack .jasp File
        try:
            copy_from_env(expected_path, jasp_file_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"File exists but could not be retrieved: {str(e)}"}

        if not zipfile.is_zipfile(jasp_file_path):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid JASP/ZIP archive."}

        # 5. Analyze JASP Content
        analysis_found = False
        correct_vars = False
        correct_clusters = False
        cluster_col_added = False
        plot_enabled = False

        try:
            with zipfile.ZipFile(jasp_file_path, 'r') as z:
                # JASP file structure contains 'index.json' or 'embedded/...'
                # We search for analysis definition files.
                # Usually located in 'analysis/X/analysis.json' or similar.
                # We'll traverse all json files to find the K-Means spec.
                
                json_files = [f for f in z.namelist() if f.endswith('.json')]
                
                for jf in json_files:
                    try:
                        with z.open(jf) as f:
                            content = json.load(f)
                            
                            # Check for Analysis Definition
                            # Structure varies by version, but look for "name": "KMeans" or "qml": "ClusteringKMeans"
                            results_obj = content.get("results", {})
                            if not results_obj: 
                                # Sometimes it's the root object or under specific keys
                                # Let's look for "title" "K-Means Clustering"
                                pass
                            
                            # Flatten/Search helper
                            content_str = json.dumps(content)
                            
                            if "K-Means Clustering" in content_str or "ClusteringKMeans" in content_str:
                                analysis_found = True
                                
                                # Analyze parameters usually found in 'options'
                                # This is heuristic as JASP internal JSON structure is complex
                                # We search for specific key-value pairs in the raw JSON string or dict
                                
                                # Check Variables
                                required_vars = ["Agreeableness", "Conscientiousness", "Extraversion", "Neuroticism", "Openness"]
                                vars_present = sum(1 for v in required_vars if v in content_str)
                                if vars_present == 5:
                                    correct_vars = True
                                
                                # Check Clusters = 3
                                # Look for "manualNumberOfClusters": 3 or similar
                                if '"manualNumberOfClusters": 3' in content_str or '"numberOfClusters": 3' in content_str:
                                    correct_clusters = True
                                # Also check if "optimization": "manual" (Fixed)
                                
                                # Check "Add predicted clusters to data"
                                # Key often: "predictionsAddedToData": true
                                if '"predictionsAddedToData": true' in content_str:
                                    cluster_col_added = True
                                
                                # Check "Cluster means" plot
                                # Key often: "plotClusterMeans": true
                                if '"plotClusterMeans": true' in content_str:
                                    plot_enabled = True
                                    
                    except Exception:
                        continue
                
                # Also check data file for the added column if possible
                # Data is usually in 'data/data.csv' or similar inside zip
                data_files = [f for f in z.namelist() if f.endswith('.csv')]
                for df in data_files:
                    with z.open(df) as f:
                        header = f.readline().decode('utf-8')
                        if "Cluster" in header:
                            cluster_col_added = True # Double verify

        except Exception as e:
            feedback.append(f"Error parsing JASP file: {str(e)}")

        # 6. Scoring Logic
        if analysis_found:
            score += 20
            feedback.append("K-Means analysis found.")
        else:
            feedback.append("No K-Means analysis found in file.")

        if correct_vars:
            score += 20
            feedback.append("All 5 personality variables used.")
        else:
            feedback.append("Incorrect variables selected.")

        if correct_clusters:
            score += 20
            feedback.append("Cluster count set to 3 (Fixed).")
        else:
            feedback.append("Cluster count incorrect or not Fixed.")

        if cluster_col_added:
            score += 10
            feedback.append("Cluster labels added to data.")
        else:
            feedback.append("Cluster labels NOT added to data.")

        if plot_enabled:
            score += 10
            feedback.append("Cluster means plot enabled.")
        else:
            feedback.append("Cluster means plot missing.")

    # 7. Final Result
    passed = score >= 65 and analysis_found # Threshold requirement
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }