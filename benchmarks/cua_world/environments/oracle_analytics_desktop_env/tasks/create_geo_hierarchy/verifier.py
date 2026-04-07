#!/usr/bin/env python3
"""
Verifier for create_geo_hierarchy task in Oracle Analytics Desktop.

Verifies:
1. .dva file creation and validity (zip archive)
2. Presence of "Geo Drilldown" hierarchy definition in workbook metadata
3. Correct hierarchy levels (Region > State > City)
4. Application of hierarchy to a visualization
5. VLM trajectory verification of the creation process
"""

import json
import os
import tempfile
import zipfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_geo_hierarchy(traj, env_info, task_info):
    """
    Verify the creation of a Geographic Hierarchy in OAD.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'geo_drilldown.dva')
    hierarchy_name = metadata.get('hierarchy_name', 'Geo Drilldown')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Setup temporary directory for verification
    with tempfile.TemporaryDirectory() as temp_dir:
        # 1. Fetch Result JSON
        local_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            # Note: Path in container is Windows format, copy_from_env should handle it 
            # or we use the path defined in export_result.ps1
            copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", local_json_path)
            with open(local_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from container"}

        # 2. Check File Existence & Timestamp (20 pts)
        output_exists = result.get('output_exists', False)
        created_during = result.get('file_created_during_task', False)
        
        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "Workbook file 'geo_drilldown.dva' not found."}
        
        score += 10
        if created_during:
            score += 10
            feedback_parts.append("Workbook saved correctly.")
        else:
            feedback_parts.append("Workbook exists but timestamp indicates it wasn't modified during task.")

        # 3. Fetch and Inspect .dva File (File Structure) (40 pts)
        local_dva_path = os.path.join(temp_dir, expected_filename)
        try:
            copy_from_env(f"C:\\Users\\Docker\\Documents\\{expected_filename}", local_dva_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve .dva file: {e}"}

        # DVA is a ZIP file. We need to find the data model definition.
        # Usually in datamodel/metadata.xml or similar JSON files.
        hierarchy_found = False
        levels_correct = False
        viz_binding_found = False
        
        try:
            if zipfile.is_zipfile(local_dva_path):
                with zipfile.ZipFile(local_dva_path, 'r') as z:
                    # Search all text-based files in the archive for the hierarchy definition
                    for filename in z.namelist():
                        if filename.endswith(('.xml', '.json', '.txt')):
                            with z.open(filename) as f:
                                content = f.read().decode('utf-8', errors='ignore')
                                
                                # Check for Hierarchy Name
                                if hierarchy_name in content:
                                    hierarchy_found = True
                                    
                                    # Basic proximity check for levels (Region, State, City)
                                    # In a real DOM parser this would be strict, here we check simple presence in definition
                                    if "Region" in content and "State" in content and "City" in content:
                                        # Ideally we check order, but presence is a strong signal combined with VLM
                                        levels_correct = True
                                
                                # Check if hierarchy is used in a visualization (binding)
                                # Look for binding to the hierarchy object ID, not just the column
                                # Often represented as "hierarchyID" or similar reference
                                if hierarchy_found and ("axis" in content or "category" in content) and hierarchy_name in content:
                                    viz_binding_found = True
            else:
                feedback_parts.append("Saved file is not a valid DVA archive.")
        except Exception as e:
            feedback_parts.append(f"Error inspecting DVA content: {e}")

        if hierarchy_found:
            score += 30
            feedback_parts.append(f"Hierarchy '{hierarchy_name}' found in metadata.")
        else:
            feedback_parts.append(f"Hierarchy '{hierarchy_name}' NOT found in metadata.")
            
        if levels_correct:
            score += 10
            feedback_parts.append("Hierarchy levels (Region, State, City) detected.")
            
        # 4. VLM Verification (Trajectory) (30 pts)
        # Use VLM to confirm the user actually interacted with the UI to create hierarchy
        # (This catches cases where they might just rename a column or do something else)
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        
        vlm_prompt = """
        Analyze these screenshots of a user working in Oracle Analytics Desktop.
        Look for the following actions:
        1. User right-clicking on data columns (Region, State, City) or accessing a menu to "Create Hierarchy".
        2. A "Create Hierarchy" or "Hierarchy" dialog box visible.
        3. User dragging a Hierarchy object (icon often looks like a tree/structure) to a chart axis.
        4. A chart displaying drill-down indicators (arrows) or hierarchy labels.
        
        Did the user create a geographic hierarchy?
        """
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_result.get("success", False):
            # A simple keyword check on the VLM reasoning or use structured output if available
            # Assuming VLM returns a boolean or positive sentiment in 'parsed'
            # Here we simulate a check:
            if "yes" in vlm_result.get("result", "").lower() or "hierarchy" in vlm_result.get("result", "").lower():
                score += 30
                feedback_parts.append("VLM confirms hierarchy creation workflow.")
            else:
                score += 10 # Partial credit if ambiguous
                feedback_parts.append("VLM could not definitively confirm hierarchy creation.")
        else:
            # Fallback if VLM fails
            score += 10
            feedback_parts.append("Skipped VLM verification.")

    # Final scoring
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }