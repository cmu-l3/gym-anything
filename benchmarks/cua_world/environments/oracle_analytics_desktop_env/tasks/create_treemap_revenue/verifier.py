#!/usr/bin/env python3
"""
Verifier for Create Treemap Visualization task in Oracle Analytics Desktop.
"""

import json
import os
import zipfile
import tempfile
import shutil
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_treemap_revenue(traj, env_info, task_info):
    """
    Verifies that the agent created a valid treemap visualization saved as a .dva file.
    
    Criteria:
    1. File 'revenue_treemap.dva' exists and was created/modified during the task.
    2. File is a valid ZIP archive (DVA format).
    3. Content analysis: The DVA internal metadata contains references to 'treemap', 'Revenue', and 'Product Category'.
    4. VLM Verification: Trajectory shows interaction with Treemap UI and final visualization.
    """
    
    # 1. Setup and Copy Files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Temp directory for processing
    work_dir = tempfile.mkdtemp()
    
    try:
        # Get JSON result
        result_json_path = os.path.join(work_dir, "task_result.json")
        try:
            copy_from_env("C:\\workspace\\task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result JSON: {str(e)}"}

        # Basic File Checks (30 points)
        score = 0
        feedback = []
        
        output_exists = result_data.get("output_exists", False)
        created_during = result_data.get("file_created_during_task", False)
        file_size = result_data.get("output_size_bytes", 0)
        
        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "Output file 'revenue_treemap.dva' not found."}
        
        score += 10 # File exists
        feedback.append("File exists.")
        
        if created_during:
            score += 10 # Fresh file
            feedback.append("File created during task.")
        else:
            feedback.append("Warning: File timestamp indicates it wasn't modified during this session.")
            
        if file_size > 5000: # > 5KB
            score += 10 # Valid size
            feedback.append("File size is valid.")
        else:
            feedback.append("File seems too small to contain a visualization.")

        # 2. DVA Content Analysis (40 points)
        # Copy the DVA file to host
        dva_host_path = os.path.join(work_dir, "revenue_treemap.dva")
        viz_valid = False
        
        try:
            # Note: Windows path in container needs to be handled by copy_from_env logic
            # Usually the framework abstraction handles "C:\..." paths if env is Windows
            copy_from_env("C:\\Users\\Docker\\Documents\\revenue_treemap.dva", dva_host_path)
            
            if zipfile.is_zipfile(dva_host_path):
                with zipfile.ZipFile(dva_host_path, 'r') as z:
                    # Search all XML/JSON files in the archive for keywords
                    found_treemap = False
                    found_revenue = False
                    found_category = False
                    
                    for filename in z.namelist():
                        if filename.endswith('.xml') or filename.endswith('.json'):
                            try:
                                content = z.read(filename).decode('utf-8', errors='ignore')
                                if re.search(r'treemap', content, re.IGNORECASE):
                                    found_treemap = True
                                if re.search(r'Revenue', content, re.IGNORECASE):
                                    found_revenue = True
                                if re.search(r'Product Category', content, re.IGNORECASE):
                                    found_category = True
                            except:
                                continue
                    
                    if found_treemap:
                        score += 20
                        feedback.append("Internal metadata confirms Treemap visualization.")
                        viz_valid = True
                    else:
                        feedback.append("Could not find 'treemap' definition inside the DVA file.")
                        
                    if found_revenue and found_category:
                        score += 20
                        feedback.append("Internal metadata confirms correct data columns used.")
                    else:
                        feedback.append("Missing references to Revenue or Product Category in metadata.")
            else:
                feedback.append("Output file is not a valid DVA (Zip) archive.")
                
        except Exception as e:
            feedback.append(f"Failed to analyze DVA file content: {str(e)}")

        # 3. VLM Verification (30 points)
        # Use trajectory to confirm UI interaction and visual result
        frames = sample_trajectory_frames(traj, n=4)
        
        vlm_prompt = """
        You are verifying an Oracle Analytics Desktop task.
        The user was asked to create a TREEMAP visualization showing Revenue by Product Category.
        
        Look at the sequence of images:
        1. Do you see a Treemap (nested rectangles of different sizes/colors)?
        2. Do you see the label "Product Category" or category names like "Technology", "Furniture"?
        3. Do you see "Revenue" being used (e.g., in the Size legend or grammar panel)?
        4. Does the final state look like a completed visualization?
        
        Return JSON:
        {
            "treemap_visible": true/false,
            "labels_visible": true/false,
            "revenue_visible": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_result and vlm_result.get('result'):
            try:
                # Naive parsing of VLM json output if it returns string
                parsed = vlm_result.get('parsed', {})
                if not parsed and isinstance(vlm_result['result'], str):
                     # Fallback if parsed is empty but result string exists
                     # (In a real impl, query_vlm handles this)
                     pass
                
                if parsed.get('treemap_visible'):
                    score += 15
                    feedback.append("VLM confirms treemap visualization is visible.")
                
                if parsed.get('labels_visible') or parsed.get('revenue_visible'):
                    score += 15
                    feedback.append("VLM confirms correct labels/measures visible.")
                    
            except Exception:
                # Fallback if VLM fails to parse
                pass

        passed = score >= 60 and viz_valid
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    finally:
        shutil.rmtree(work_dir, ignore_errors=True)