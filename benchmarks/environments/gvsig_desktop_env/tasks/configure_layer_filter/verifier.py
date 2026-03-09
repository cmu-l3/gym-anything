#!/usr/bin/env python3
"""
Verifier for configure_layer_filter task.

Verification Strategy:
1. Project File Analysis (Primary):
   - Check if 'sa_regional.gvsproj' exists and was created during the task.
   - Inspect the internal XML of the .gvsproj (it is a ZIP archive) to ensure:
     a) It references the original 'ne_110m_admin_0_countries.shp' (Anti-gaming: ensuring agent didn't export a new shapefile).
     b) It contains the filter string "South America" in the layer definition.

2. Visual Verification (Secondary):
   - Use VLM to check if the map view shows ONLY South America (filtering worked visually).
"""

import json
import os
import zipfile
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_layer_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filter = metadata.get('required_filter_text', "South America")
    original_shapefile = metadata.get('original_shapefile', "ne_110m_admin_0_countries.shp")

    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # Check 1: File Existence & Timestamp (20 pts)
    if not result.get('project_exists', False):
        return {"passed": False, "score": 0, "feedback": "Project file not saved"}
    
    if not result.get('project_created_during_task', False):
        feedback_parts.append("Warning: Project file timestamp is old (pre-task?)")
        score += 5
    else:
        score += 20
        feedback_parts.append("Project saved successfully")

    # Check 2: Analyze Project Content (50 pts)
    # gvSIG projects (.gvsproj) are typically ZIP files containing XML configuration
    temp_proj = tempfile.NamedTemporaryFile(delete=False, suffix='.gvsproj')
    filter_found = False
    source_correct = False
    
    try:
        copy_from_env(result['project_path'], temp_proj.name)
        
        if zipfile.is_zipfile(temp_proj.name):
            with zipfile.ZipFile(temp_proj.name, 'r') as z:
                # Search all XML files in the project structure for the filter and source
                for filename in z.namelist():
                    if filename.endswith('.xml') or filename.endswith('.gvp'):
                        try:
                            content = z.read(filename).decode('utf-8', errors='ignore')
                            
                            # Check for filter
                            if expected_filter in content:
                                filter_found = True
                            
                            # Check for data source
                            if original_shapefile in content:
                                source_correct = True
                                
                            if filter_found and source_correct:
                                break
                        except Exception:
                            continue
        else:
            # Fallback: maybe it's just a raw XML file in some versions?
            with open(temp_proj.name, 'r', errors='ignore') as f:
                content = f.read()
                if expected_filter in content:
                    filter_found = True
                if original_shapefile in content:
                    source_correct = True

    except Exception as e:
        feedback_parts.append(f"Error analyzing project file: {e}")
    finally:
        if os.path.exists(temp_proj.name):
            os.unlink(temp_proj.name)

    if filter_found:
        score += 30
        feedback_parts.append(f"Filter '{expected_filter}' found in project configuration")
    else:
        feedback_parts.append(f"Filter '{expected_filter}' NOT found in project file")

    if source_correct:
        score += 20
        feedback_parts.append("Project correctly references original shapefile")
    else:
        feedback_parts.append("Project does NOT reference original shapefile (did you create a new file instead of filtering?)")

    # Check 3: VLM Visual Verification (30 pts)
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if final:
        vlm_prompt = (
            "You are verifying a GIS task in gvSIG Desktop. "
            "The goal was to filter a world map to show ONLY South America.\n"
            "1. Look at the map view. Are South American countries visible?\n"
            "2. Are other continents (Africa, North America, etc.) HIDDEN/GONE?\n"
            "3. If North America or Africa are still visible, the filter failed.\n"
            "Respond with 'YES' if the map shows ONLY South America, otherwise 'NO'."
        )
        
        vlm_response = query_vlm(images=[final], prompt=vlm_prompt).get("text", "").upper()
        
        if "YES" in vlm_response:
            score += 30
            feedback_parts.append("Visual verification passed: Map shows only South America")
        else:
            feedback_parts.append("Visual verification failed: Other continents appear visible")
    else:
        feedback_parts.append("No screenshots available for visual verification")

    passed = (score >= 80) and filter_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }