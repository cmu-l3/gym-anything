#!/usr/bin/env python3
"""
Verifier for Oracle Analytics Desktop Customer Clustering Task.

Criteria:
1. File Verification (40 pts): 'Customer_Segmentation.dva' exists, is a valid zip, created during task.
2. Content Verification (30 pts): DVA contains 'scatter' chart and 'cluster' analytics configuration with 5 clusters.
3. VLM Verification (30 pts): Trajectory shows scatter plot with clusters (colored points).
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_customer_clustering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_path', r"C:\Users\Docker\Documents\Customer_Segmentation.dva")
    expected_filename = os.path.basename(expected_path)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Retrieve Result JSON and DVA File
    # ---------------------------------------------------------
    temp_dir = tempfile.mkdtemp()
    try:
        # Get result.json
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("C:\\tmp\\task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        output_exists = result_data.get("output_exists", False)
        file_created = result_data.get("file_created_during_task", False)
        app_running = result_data.get("app_was_running", False)

        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "Workbook file not found."}

        # Retrieve the actual DVA file
        dva_local_path = os.path.join(temp_dir, expected_filename)
        try:
            copy_from_env(expected_path, dva_local_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"File exists but failed to copy: {str(e)}"}

        # ---------------------------------------------------------
        # 2. File & Metadata Checks (30 pts)
        # ---------------------------------------------------------
        if output_exists:
            score += 10
            feedback_parts.append("File created")
        
        if file_created:
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("Warning: File timestamp indicates it was not modified during this session")

        if app_running:
            score += 10
            feedback_parts.append("App was running")

        # ---------------------------------------------------------
        # 3. Deep Content Analysis (40 pts)
        # ---------------------------------------------------------
        # DVA files are ZIP archives. We check internal XML/JSON for configuration.
        content_score = 0
        content_feedback = []
        
        if zipfile.is_zipfile(dva_local_path):
            try:
                with zipfile.ZipFile(dva_local_path, 'r') as z:
                    # Search for visualization metadata
                    # Usually in /datamodel/ or specific xml files
                    found_scatter = False
                    found_cluster = False
                    found_cluster_count = False
                    
                    # Read all text content from relevant files
                    file_contents = ""
                    for filename in z.namelist():
                        if filename.endswith(".xml") or filename.endswith(".json"):
                            try:
                                with z.open(filename) as f:
                                    file_contents += f.read().decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for scatter plot
                    if re.search(r'scatter', file_contents, re.IGNORECASE):
                        found_scatter = True
                        content_score += 10
                        content_feedback.append("Scatter plot detected")
                    
                    # Check for clustering
                    # Oracle Analytics uses terms like "cluster", "k-means", "numClusters"
                    if re.search(r'cluster', file_contents, re.IGNORECASE):
                        found_cluster = True
                        content_score += 15
                        content_feedback.append("Clustering analytics detected")
                        
                        # Check for count 5
                        # Matches: "numClusters":5 or "numClusters": "5" or similar
                        if re.search(r'["\']?numClusters["\']?\s*[:=]\s*["\']?5["\']?', file_contents, re.IGNORECASE):
                            found_cluster_count = True
                            content_score += 15
                            content_feedback.append("Cluster count set to 5")
                        else:
                            content_feedback.append("Could not verify specific cluster count (5)")

            except Exception as e:
                content_feedback.append(f"Error parsing DVA content: {e}")
        else:
            content_feedback.append("Invalid DVA file format (not a zip)")
        
        score += content_score
        feedback_parts.extend(content_feedback)

        # ---------------------------------------------------------
        # 4. VLM Trajectory Verification (30 pts)
        # ---------------------------------------------------------
        vlm_score = 0
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        if final_shot:
            frames.append(final_shot)

        if frames:
            prompt = """
            Analyze these screenshots of Oracle Analytics Desktop.
            The user is tasked with creating a Scatter Plot of Sales vs Profit by Customer, and applying Clustering (5 groups).
            
            Check for:
            1. A Scatter Plot visualization (dots on a chart).
            2. High density of points (representing individual customers, not just a few categories).
            3. Different colors applied to the dots (indicating clusters).
            4. A legend showing "Cluster 1", "Cluster 2", etc.
            
            Return JSON:
            {
                "scatter_plot_visible": true/false,
                "high_density_points": true/false,
                "clustering_colors_visible": true/false,
                "cluster_legend_visible": true/false
            }
            """
            
            result = query_vlm(images=frames, prompt=prompt)
            parsed = result.get('parsed', {})
            
            if parsed.get('scatter_plot_visible'):
                vlm_score += 10
            if parsed.get('high_density_points'):
                vlm_score += 5
            if parsed.get('clustering_colors_visible') or parsed.get('cluster_legend_visible'):
                vlm_score += 15
                feedback_parts.append("Visual confirmation of clustering")
            else:
                feedback_parts.append("VLM did not clearly see clustering colors/legend")
        
        score += vlm_score

    finally:
        shutil.rmtree(temp_dir)

    passed = score >= 70 and output_exists and file_created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }