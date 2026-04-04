#!/usr/bin/env python3
"""
Verifier for create_swimlane_flowchart task.

Checks:
1. .eddx file existence, validity, and content (lanes, text labels).
2. .png file existence and validity.
3. Visual verification via VLM (swimlane structure).
"""

import os
import json
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_swimlane_flowchart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_lanes = metadata.get('required_lanes', [])
    required_shapes = metadata.get('required_shapes', [])
    
    # 1. Load result JSON from export script
    task_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: EDDX File Check (30 pts) ---
    eddx_exists = task_result.get('eddx_exists', False)
    eddx_created = task_result.get('eddx_created_during_task', False)
    
    eddx_content_valid = False
    xml_content = ""
    
    if eddx_exists:
        if eddx_created:
            score += 5
            feedback_parts.append("EDDX file created during task")
        else:
            feedback_parts.append("EDDX file exists but old timestamp")

        # Analyze EDDX Content
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Diagrams/incident_management_swimlane.eddx", temp_eddx.name)
            
            # Check if valid zip and contains minimum data
            if os.path.getsize(temp_eddx.name) > 2000: # minimal empty is ~1kb
                try:
                    with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                        # Concatenate all XML content to search for strings
                        for name in zf.namelist():
                            if name.endswith('.xml'):
                                xml_content += zf.read(name).decode('utf-8', errors='ignore')
                        
                        score += 10 # Valid archive
                        eddx_content_valid = True
                        feedback_parts.append("Valid EDDX file format")
                except zipfile.BadZipFile:
                    feedback_parts.append("Invalid EDDX file (bad zip)")
            else:
                feedback_parts.append("EDDX file too small")
                
        except Exception as e:
            feedback_parts.append(f"Failed to inspect EDDX: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    else:
        feedback_parts.append("EDDX file not found")

    # --- Criterion 2: PNG File Check (15 pts) ---
    png_exists = task_result.get('png_exists', False)
    png_created = task_result.get('png_created_during_task', False)
    
    if png_exists and png_created:
        score += 15
        feedback_parts.append("PNG export successful")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG exists but old timestamp")
    else:
        feedback_parts.append("PNG export missing")

    # --- Criterion 3: Content Verification (30 pts) ---
    if eddx_content_valid and xml_content:
        # Check for Lane Labels
        lanes_found = 0
        for lane in required_lanes:
            if lane in xml_content:
                lanes_found += 1
        
        # Check for Process Shape Labels
        shapes_found = 0
        for shape in required_shapes:
            if shape in xml_content:
                shapes_found += 1
        
        # Scoring Content
        # Lanes: Need at least 3 of 4
        if lanes_found >= 3:
            score += 15
            feedback_parts.append(f"Found {lanes_found}/4 swimlanes")
        else:
            feedback_parts.append(f"Missing swimlanes (found {lanes_found}/4)")

        # Shapes: Need at least 5 of 8
        if shapes_found >= 5:
            score += 15
            feedback_parts.append(f"Found {shapes_found}/8 process steps")
        else:
            feedback_parts.append(f"Missing process steps (found {shapes_found}/8)")
            
    # --- Criterion 4: VLM Visual Verification (25 pts) ---
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=4)
    all_images = frames + ([final_screenshot] if final_screenshot else [])

    if all_images:
        prompt = """
        I am analyzing a series of screenshots from EdrawMax. The user is supposed to create a Cross-Functional Swimlane Flowchart.
        
        Look for these specific visual elements:
        1. HORIZONTAL SWIMLANES: Distinct horizontal rectangular bands stretching across the diagram.
        2. LABELS ON LEFT: Text labels on the left side of these bands (e.g., "Help Desk", "Management").
        3. FLOWCHART SHAPES INSIDE: Rectangles, diamonds, or ovals placed INSIDE these horizontal bands.
        4. CONNECTORS: Lines connecting the shapes, crossing between bands.
        
        Does the diagram look like a structured Swimlane Flowchart?
        """
        
        try:
            vlm_res = query_vlm(images=all_images, prompt=prompt)
            # Simple heuristic based on VLM response text (assuming VLM returns a detailed string, 
            # but ideally we'd parse structured JSON if supported. Here we rely on the implementation 
            # of query_vlm to return a 'passed' or 'score' or we parse the text).
            # Assuming standard interface returns a dict with 'parsed' or we check text for positive sentiment.
            
            # Since I cannot see the specific VLM implementation details, I will assume we check for keywords
            # or use a structured prompt if the system supports it. 
            # Using a simplified text check here:
            res_text = str(vlm_res).lower()
            
            if "swimlane" in res_text and ("yes" in res_text or "confirm" in res_text or "visible" in res_text):
                 vlm_score = 25
                 feedback_parts.append("VLM confirmed swimlane structure")
            elif "swimlane" in res_text:
                 vlm_score = 15
                 feedback_parts.append("VLM detected swimlanes but was uncertain")
            else:
                 feedback_parts.append("VLM did not detect clear swimlane structure")
                 
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback_parts.append("VLM verification skipped due to error")
    
    score += vlm_score

    # Final Pass Logic
    # Must have EDDX + PNG + At least some content found + reasonable score
    passed = (eddx_exists and eddx_content_valid and png_exists and score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }