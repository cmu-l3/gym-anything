#!/usr/bin/env python3
"""
Verifier for Create Multilayer Map task in Oracle Analytics Desktop.

Verifies:
1. Geospatial_Analysis.dva exists and was created during task.
2. DVA file is a valid ZIP and contains map visualization metadata.
3. Metadata confirms two layers:
   - Layer 1: State dimension + Sales measure
   - Layer 2: City dimension + Profit measure
4. VLM visual verification of map layers.
"""

import json
import os
import zipfile
import tempfile
import logging
import re
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_multilayer_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Score components
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON and DVA File
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.dva')
    
    try:
        # Get result JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check file existence (10 pts)
        if not result.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Workbook file 'Geospatial_Analysis.dva' not found."}
        
        score += 10
        feedback_parts.append("File created")

        # Check creation time (anti-gaming) (10 pts)
        if result.get('file_created_during_task'):
            score += 10
            feedback_parts.append("File created during task window")
        else:
            feedback_parts.append("WARNING: File timestamp suggests it was not modified during task")

        # 2. Analyze DVA Content (40 pts)
        # The DVA is a zip. We need to extract it and look for visualization metadata.
        dva_valid = False
        map_found = False
        state_layer_found = False
        city_layer_found = False
        sales_measure_found = False
        profit_measure_found = False
        
        try:
            copy_from_env("/tmp/Geospatial_Analysis.dva", temp_dva.name)
            if zipfile.is_zipfile(temp_dva.name):
                dva_valid = True
                score += 5 # Valid DVA format
                
                with zipfile.ZipFile(temp_dva.name, 'r') as z:
                    # Search for xml or json files containing viz definitions
                    # Common paths: /datamodel/content.xml, /xml/..., or *.json in newer versions
                    content_files = [f for f in z.namelist() if f.endswith('.xml') or f.endswith('.json')]
                    
                    full_text = ""
                    for cf in content_files:
                        try:
                            with z.open(cf) as f:
                                full_text += f.read().decode('utf-8', errors='ignore')
                        except:
                            continue
                            
                    # Crude but effective string searching in metadata
                    # Look for map viz signature
                    if 'vizType="map"' in full_text or '"vizType":"map"' in full_text or 'oracle.bitech.viz.map' in full_text:
                        map_found = True
                        score += 15
                        feedback_parts.append("Map visualization found")
                    
                    # Look for dimensions (case insensitive)
                    if re.search(r'State', full_text, re.IGNORECASE):
                        state_layer_found = True
                    if re.search(r'City', full_text, re.IGNORECASE):
                        city_layer_found = True
                        
                    # Look for measures
                    if re.search(r'Sales', full_text, re.IGNORECASE):
                        sales_measure_found = True
                    if re.search(r'Profit', full_text, re.IGNORECASE):
                        profit_measure_found = True
                        
                    # Evaluate layers (20 pts)
                    if state_layer_found and city_layer_found:
                        score += 20
                        feedback_parts.append("Both State and City dimensions found in workbook")
                    elif state_layer_found or city_layer_found:
                        score += 10
                        feedback_parts.append("Partial dimensions found (missing City or State)")
                    else:
                        feedback_parts.append("No expected dimensions (State/City) found in metadata")

        except Exception as e:
            feedback_parts.append(f"Failed to parse DVA file: {e}")

    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_dva.name): os.unlink(temp_dva.name)

    # 3. VLM Verification (40 pts)
    # Use trajectory to confirm the visual layering
    vlm_score = 0
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
        
    if frames:
        prompt = """
        Analyze these screenshots of Oracle Analytics Desktop.
        The user is creating a multi-layer map.
        
        Look for:
        1. A map of the USA.
        2. States are colored in (filled shapes).
        3. Points/Circles are overlaid on the map (representing cities).
        4. The points and the states look like distinct layers (e.g., dots on top of shapes).
        
        Answer JSON:
        {
            "map_visible": true/false,
            "filled_states_visible": true/false,
            "points_overlaid_visible": true/false,
            "distinct_layers": true/false
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, images=frames)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('map_visible'):
                vlm_score += 10
            if parsed.get('filled_states_visible'):
                vlm_score += 10
            if parsed.get('points_overlaid_visible'):
                vlm_score += 10
            if parsed.get('distinct_layers'):
                vlm_score += 10
                
            feedback_parts.append(f"Visual verification score: {vlm_score}/40")
        else:
            feedback_parts.append("Visual verification failed (VLM error)")
    else:
        feedback_parts.append("No screenshots available for visual verification")
        
    score += vlm_score
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }