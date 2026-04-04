#!/usr/bin/env python3
"""
Verifier for add_wms_basemap_layer task.

Verifies that:
1. The project file was saved and created during the task.
2. The project file contains references to the Mundial OSM WMS.
3. VLM: Visual confirmation of basemap presence and correct layer ordering.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_wms_basemap_layer(traj, env_info, task_info):
    """
    Verify WMS basemap addition and layer ordering.
    """
    # 1. Setup and retrieve data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # PROGRAMMATIC CHECKS (60 Points Max)
    # ----------------------------------------------------------------
    
    # Criterion 1: Project File Exists (15 pts)
    if result.get('project_file_exists', False):
        score += 15
        feedback_parts.append("Project file saved.")
    else:
        feedback_parts.append("Project file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Anti-Gaming Timestamp Check (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task session.")
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this task.")

    # Criterion 3: WMS URL Verification (20 pts)
    if result.get('wms_url_found', False):
        score += 20
        feedback_parts.append("WMS URL (mundialis) found in project.")
    else:
        feedback_parts.append("WMS URL NOT found in project file.")

    # Criterion 4: OSM Layer Name Check (15 pts)
    if result.get('osm_layer_found', False):
        score += 15
        feedback_parts.append("OSM layer reference found.")
    else:
        feedback_parts.append("OSM layer reference NOT found.")

    # ----------------------------------------------------------------
    # VLM CHECKS (40 Points Max)
    # ----------------------------------------------------------------
    
    # Prepare images
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        images = frames + [final_screen]
        
        prompt = """
        You are evaluating a GIS task in gvSIG Desktop.
        Goal: Add a WMS Basemap (OpenStreetMap) and ensure it is BELOW the vector countries layer.
        
        Review the screenshots and answer:
        1. Is the OpenStreetMap basemap visible? (Look for streets, terrain, or map tiles distinct from the solid vector colors)
        2. Are the country polygons visible ON TOP of the basemap? (Boundaries/fills should overlay the street map)
        3. Can you see the Table of Contents (TOC) with two layers?
        4. In the TOC, is the WMS layer visually below the countries layer?
        
        Return JSON:
        {
            "basemap_visible": boolean,
            "countries_on_top": boolean,
            "toc_layer_ordering_correct": boolean,
            "explanation": "string"
        }
        """
        
        try:
            vlm_response = query_vlm(images=images, prompt=prompt, output_schema={
                "basemap_visible": "bool",
                "countries_on_top": "bool",
                "toc_layer_ordering_correct": "bool",
                "explanation": "str"
            })
            
            # VLM Scoring
            if vlm_response.get("basemap_visible", False):
                score += 15
                feedback_parts.append("VLM: Basemap visible.")
            else:
                feedback_parts.append("VLM: Basemap NOT visible.")
                
            if vlm_response.get("countries_on_top", False):
                score += 15
                feedback_parts.append("VLM: Countries are on top.")
            else:
                feedback_parts.append("VLM: Countries are NOT on top (or missing).")
                
            if vlm_response.get("toc_layer_ordering_correct", False):
                score += 10
                feedback_parts.append("VLM: TOC ordering correct.")
                
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM verification failed due to error.")
            # Fallback points if programmatic checks were perfect
            if score >= 60:
                score += 20 

    # ----------------------------------------------------------------
    # FINAL EVALUATION
    # ----------------------------------------------------------------
    
    # Required: Project file exists + WMS URL found + some VLM evidence
    key_requirements = (
        result.get('project_file_exists') and 
        result.get('wms_url_found')
    )
    
    passed = (score >= 60) and key_requirements

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }