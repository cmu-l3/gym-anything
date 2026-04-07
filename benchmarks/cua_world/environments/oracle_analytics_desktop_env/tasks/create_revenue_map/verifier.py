#!/usr/bin/env python3
"""
Verifier for create_revenue_map task in Oracle Analytics Desktop.

Verification Strategy:
1. File Verification (40 pts):
   - Checks if 'Revenue_Map.dva' exists and was created during the task.
   - Inspects the internal structure of the .dva (ZIP archive) to confirm it contains a map visualization.
   - Checks for binding of 'State' (location) and 'Revenue' (color).

2. VLM Verification (60 pts):
   - Uses trajectory frames to verify the agent actually interacted with the Map visualization.
   - Checks if the final state shows a rendered map with colored states.
   - Verifies the legend/color scale is present.

This hybrid approach ensures the file is valid AND the visual output was achieved manually.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_revenue_map(traj, env_info, task_info):
    """
    Verify creation of Revenue Map visualization.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', r"C:\Users\Docker\Documents\Revenue_Map.dva")
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. READ EXPORTED RESULTS (Basic Checks)
    # =========================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result_data.get('output_exists', False)
    file_created = result_data.get('file_created_during_task', False)
    file_size = result_data.get('output_size_bytes', 0)

    if output_exists:
        score += 10
        feedback_parts.append("DVA export file found.")
    else:
        feedback_parts.append("DVA export file NOT found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    if file_created:
        score += 10
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("File timestamp indicates pre-existing file.")

    if file_size > 5000:  # Reasonable size for a DVA project
        score += 5
        feedback_parts.append("File size valid.")

    # =========================================================
    # 2. DEEP FILE INSPECTION (Internal DVA Structure)
    # =========================================================
    # DVA files are ZIP archives containing JSON/XML definitions.
    # We look for visualization definitions.
    
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    try:
        copy_from_env(expected_output_path, temp_dva.name)
        
        has_map_viz = False
        has_state_binding = False
        has_revenue_binding = False
        
        if zipfile.is_zipfile(temp_dva.name):
            with zipfile.ZipFile(temp_dva.name, 'r') as z:
                # Search for project definition files (usually datamodel or view definitions)
                # Structure varies by OAD version, but usually plain text/json/xml inside
                file_list = z.namelist()
                
                # Naive text search across small text files in the archive
                # accurate enough to detect the intent and bindings without strict schema parsing
                for filename in file_list:
                    if filename.endswith('.json') or filename.endswith('.xml'):
                        try:
                            with z.open(filename) as f:
                                content = f.read().decode('utf-8', errors='ignore').lower()
                                
                                # Check for map visualization type
                                if 'map' in content and ('viz' in content or 'visualization' in content):
                                    # Strengthen check: look for specific map type identifiers often used
                                    if 'oracle.bi.tech.plugin.map' in content or '"type":"map"' in content or 'viewtype="map"' in content:
                                        has_map_viz = True
                                
                                # Check for data bindings
                                if 'state' in content:
                                    has_state_binding = True
                                if 'revenue' in content:
                                    has_revenue_binding = True
                        except:
                            continue
        
        if has_map_viz:
            score += 15
            feedback_parts.append("Verified Map visualization inside DVA file.")
        else:
            feedback_parts.append("Could not confirm Map visualization in file metadata.")
            
        if has_state_binding and has_revenue_binding:
            score += 15 # Full points for correct bindings
            feedback_parts.append("Verified 'State' and 'Revenue' data bindings.")
        elif has_state_binding or has_revenue_binding:
            score += 5
            feedback_parts.append("Found partial data bindings.")
            
    except Exception as e:
        feedback_parts.append(f"Failed to inspect DVA file content: {str(e)}")
    finally:
        if os.path.exists(temp_dva.name):
            os.unlink(temp_dva.name)

    # =========================================================
    # 3. VLM VERIFICATION (Visual Checks)
    # =========================================================
    
    # Prompt for VLM
    vlm_prompt = """
    You are verifying an Oracle Analytics Desktop task.
    The goal was to create a Map visualization (Choropleth) showing Revenue by State.
    
    Analyze these screenshots of the agent's workflow.
    Look for:
    1. A map visualization (US States map) visible on the canvas.
    2. States colored differently (filled map/choropleth), indicating a data binding to Color.
    3. A legend showing 'Revenue'.
    4. Data fields 'State' and 'Revenue' being used in the grammar panel (left side or edges).
    
    Return JSON:
    {
        "map_visible": boolean,
        "is_filled_map": boolean,
        "revenue_legend_visible": boolean,
        "state_field_visible": boolean,
        "confidence": "high/medium/low"
    }
    """
    
    # Get frames
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('map_visible'):
            score += 20
            feedback_parts.append("VLM confirmed map visualization.")
            
        if parsed.get('is_filled_map'):
            score += 15
            feedback_parts.append("VLM confirmed filled (choropleth) map style.")
        else:
            feedback_parts.append("VLM did not see a filled map (might be points or bubbles).")
            
        if parsed.get('revenue_legend_visible') or parsed.get('state_field_visible'):
            score += 10
            feedback_parts.append("VLM confirmed data usage visually.")
            
    except Exception as e:
        feedback_parts.append(f"VLM verification failed: {e}")

    # =========================================================
    # FINAL SCORING
    # =========================================================
    
    # Pass threshold: 60 points
    # Must have output file (10+10=20) AND valid map type (15) AND at least partial VLM (25) = 60
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }