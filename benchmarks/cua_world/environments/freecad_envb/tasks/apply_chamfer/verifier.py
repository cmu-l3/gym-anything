#!/usr/bin/env python3
"""
Verifier for apply_chamfer task.

Verifies:
1. Output files exist and were created during task.
2. FCStd file contains a 'Part::Chamfer' object with size 2.0mm.
3. STEP file is a valid STEP export.
4. VLM verification of the workflow.
"""

import json
import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_apply_chamfer(traj, env_info, task_info):
    # 1. Setup and imports
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chamfer_size = metadata.get('chamfer_size_mm', 2.0)
    
    score = 0
    feedback = []
    
    # 2. Retrieve JSON result
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json', delete=True) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            tmp.seek(0)
            task_result = json.load(tmp)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    # 3. Verify FCStd File (Topological Check)
    fcstd_ok = False
    chamfer_found = False
    chamfer_correct = False
    
    if task_result.get('fcstd_exists') and task_result.get('fcstd_created_during_task'):
        score += 10
        feedback.append("FCStd file saved.")
        
        # Analyze FCStd content
        with tempfile.NamedTemporaryFile(suffix='.FCStd', delete=True) as fcstd_tmp:
            try:
                copy_from_env(metadata['output_fcstd'], fcstd_tmp.name)
                
                # FCStd is a ZIP file. We look for Document.xml
                if zipfile.is_zipfile(fcstd_tmp.name):
                    with zipfile.ZipFile(fcstd_tmp.name, 'r') as z:
                        if 'Document.xml' in z.namelist():
                            with z.open('Document.xml') as f:
                                tree = ET.parse(f)
                                root = tree.getroot()
                                
                                # Search for Chamfer object
                                # Structure: <Object type="Part::Chamfer" ...>
                                #              <Properties>
                                #                <Property name="Size" ...>
                                #                  <Float value="2.0"/>
                                for obj in root.findall(".//Object"):
                                    obj_type = obj.get('type')
                                    if obj_type == 'Part::Chamfer':
                                        chamfer_found = True
                                        
                                        # Check Size property
                                        # Note: XML structure varies by version, usually nested in Properties
                                        # We look for value="2" or value="2.0"
                                        props = obj.find('Properties')
                                        if props:
                                            for prop in props.findall('Property'):
                                                if prop.get('name') == 'Size':
                                                    float_val = prop.find('Float')
                                                    if float_val is not None:
                                                        val = float(float_val.get('value', '0'))
                                                        if abs(val - expected_chamfer_size) < 0.1:
                                                            chamfer_correct = True
                                                        else:
                                                            feedback.append(f"Chamfer size is {val}mm, expected {expected_chamfer_size}mm.")
                                break
            except Exception as e:
                feedback.append(f"Error analyzing FCStd file: {str(e)}")

    if chamfer_found:
        score += 20
        feedback.append("Chamfer operation found in document.")
    if chamfer_correct:
        score += 20
        feedback.append("Chamfer size is correct (2mm).")
        fcstd_ok = True
    elif not chamfer_found and task_result.get('fcstd_exists'):
        feedback.append("No Chamfer object found in the saved file.")

    # 4. Verify STEP File
    step_ok = False
    if task_result.get('step_exists') and task_result.get('step_created_during_task'):
        score += 10
        feedback.append("STEP export created.")
        
        if task_result.get('step_valid_header'):
            score += 10
            feedback.append("STEP file format valid.")
            step_ok = True
            
            # Additional size check - a chamfered box should be > 1KB
            if task_result.get('step_size_bytes', 0) > 1000:
                score += 5
                feedback.append("STEP file contains geometry.")
            else:
                feedback.append("STEP file seems empty.")
    else:
        feedback.append("STEP export missing.")

    # 5. VLM Verification (Visual & Workflow)
    vlm_score = 0
    
    # Get trajectory images
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if frames or final:
        images = frames + ([final] if final else [])
        
        prompt = """
        Review this sequence of screenshots from FreeCAD.
        The user was asked to:
        1. Open a model with two blocks.
        2. Select the Top block.
        3. Apply a Chamfer (beveled edges) to it.
        4. Export the result.
        
        Check for:
        - Did the user open the file? (See blocks in view)
        - Did the user activate the Chamfer tool? (Chamfer dialog or icon)
        - Does the final object look chamfered (edges are not sharp lines, but have small angled faces)?
        - Did they perform an export action?
        
        Respond JSON: {"chamfer_visible": bool, "workflow_followed": bool, "confidence": float}
        """
        
        try:
            vlm_res = query_vlm(images=images, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('chamfer_visible'):
                vlm_score += 15
                feedback.append("Visual confirmation: Chamfer applied.")
            
            if parsed.get('workflow_followed'):
                vlm_score += 10
                feedback.append("Visual confirmation: Workflow followed.")
                
        except Exception as e:
            feedback.append(f"VLM verification failed: {str(e)}")
            # Fallback points if programmatic checks passed strongly
            if fcstd_ok and step_ok:
                vlm_score += 25
    
    score += vlm_score

    # Final tally
    passed = (score >= 60) and fcstd_ok
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }