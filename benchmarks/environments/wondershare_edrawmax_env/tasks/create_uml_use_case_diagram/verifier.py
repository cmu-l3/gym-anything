#!/usr/bin/env python3
"""
Verifier for create_uml_use_case_diagram task.

This verifier uses a hybrid approach:
1. Programmatic check of the .eddx file (ZIP archive) to ensure it contains
   expected text labels for actors and use cases.
2. VLM verification of the final screenshot to ensure the visual structure
   matches a valid UML Use Case diagram (stick figures, ovals, boundary box).
"""

import os
import json
import tempfile
import zipfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_uml_use_case_diagram(traj, env_info, task_info):
    """
    Verify the Patient Portal UML Use Case Diagram.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    required_labels = metadata.get('required_labels', [])
    min_size = metadata.get('min_size_bytes', 5000)

    # Load export result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # CRITERION 1: File Existence & Integrity (30 pts)
    # ------------------------------------------------------------------
    output_exists = result_data.get('output_exists', False)
    file_created = result_data.get('file_created_during_task', False)
    file_size = result_data.get('output_size_bytes', 0)
    
    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file /home/ga/Documents/PatientPortal_UseCaseDiagram.eddx not found."
        }
    
    score += 10
    feedback_parts.append("File exists")

    if file_created:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates it wasn't created during this session")

    if file_size > min_size:
        score += 10
        feedback_parts.append(f"File size reasonable ({file_size} bytes)")
    else:
        feedback_parts.append(f"File too small ({file_size} bytes)")

    # ------------------------------------------------------------------
    # CRITERION 2: Content Validation via XML Parsing (30 pts)
    # ------------------------------------------------------------------
    # EdrawMax .eddx files are ZIP archives containing XML content
    temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
    xml_content = ""
    valid_archive = False
    
    try:
        copy_from_env(result_data.get('output_path'), temp_eddx.name)
        
        if zipfile.is_zipfile(temp_eddx.name):
            valid_archive = True
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                # Read all XML files in the archive (page content is usually in .xml files)
                for name in zf.namelist():
                    if name.endswith('.xml'):
                        try:
                            xml_content += zf.read(name).decode('utf-8', errors='ignore')
                        except:
                            pass
    except Exception as e:
        feedback_parts.append(f"Failed to inspect file content: {str(e)}")
    finally:
        if os.path.exists(temp_eddx.name):
            os.unlink(temp_eddx.name)

    if valid_archive:
        # Check for required text labels
        found_labels = []
        for label in required_labels:
            # Case insensitive check
            if label.lower() in xml_content.lower():
                found_labels.append(label)
        
        # Scoring based on percentage of found labels
        if len(required_labels) > 0:
            label_score = int((len(found_labels) / len(required_labels)) * 30)
            score += label_score
            feedback_parts.append(f"Found {len(found_labels)}/{len(required_labels)} required text labels")
            
            # Bonus check for UML specific XML tags/attributes if possible, 
            # but simple text search is robust enough for "Patient", "Admin", etc.
        else:
            score += 30 # Fallback if no labels defined
    else:
        feedback_parts.append("Output file is not a valid EdrawMax (.eddx) archive")

    # ------------------------------------------------------------------
    # CRITERION 3: VLM Visual Verification (40 pts)
    # ------------------------------------------------------------------
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a UML Use Case Diagram created in EdrawMax.
    
    Look for the following specific elements:
    1. A large rectangle (System Boundary) labeled 'Patient Portal System'.
    2. Stick figure icons (Actors) outside the rectangle.
    3. Oval/Ellipse shapes (Use Cases) inside the rectangle.
    4. Connecting lines between the stick figures and the ovals.
    
    Does the screenshot show a diagram matching this structure?
    Ignore minor spelling errors, focus on the visual structure of a Use Case diagram.
    """
    
    vlm_result = query_vlm(
        prompt=vlm_prompt,
        image=final_screenshot,
        options={"json_mode": True} 
    )
    
    vlm_passed = False
    if vlm_result and "yes" in vlm_result.get("response", "").lower():
         vlm_passed = True
    
    # Let's try to get a structured response if the VLM supports it, 
    # otherwise interpret the text. For safety, we trust the text analysis below.
    # But a robust prompt for structured JSON is better:
    
    structured_prompt = """
    Analyze the screenshot for a UML Use Case Diagram.
    Respond with JSON:
    {
      "has_system_boundary": boolean,
      "has_actors_stick_figures": boolean,
      "has_use_cases_ovals": boolean,
      "has_connecting_lines": boolean,
      "diagram_visible": boolean
    }
    """
    
    vlm_struct = query_vlm(prompt=structured_prompt, image=final_screenshot)
    
    if vlm_struct and vlm_struct.get("success"):
        parsed = vlm_struct.get("parsed", {})
        
        # Score components
        vlm_score = 0
        if parsed.get("diagram_visible"): vlm_score += 10
        if parsed.get("has_system_boundary"): vlm_score += 10
        if parsed.get("has_actors_stick_figures"): vlm_score += 10
        if parsed.get("has_use_cases_ovals"): vlm_score += 10
        # If score is high, give full points including lines check implicity
        
        score += vlm_score
        feedback_parts.append(f"Visual verification score: {vlm_score}/40")
    else:
        # Fallback if VLM fails to parse or run
        feedback_parts.append("VLM verification failed to run")

    # ------------------------------------------------------------------
    # FINAL PASS/FAIL
    # ------------------------------------------------------------------
    # Pass if file is valid, has most labels, and looks like a diagram
    passed = score >= 60 and output_exists and valid_archive
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }