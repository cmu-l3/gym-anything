#!/usr/bin/env python3
"""
Verifier for create_uml_state_diagram task.

Verification Strategy:
1. File Existence & Anti-Gaming: Check timestamps of .eddx and .png files.
2. Content Analysis (Programmatic): Unzip .eddx and parse XML to find state names and transition labels.
3. Visual Analysis (VLM): Use trajectory frames to confirm the agent built a state machine diagram.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_uml_state_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_states = metadata.get('required_states', [])
    required_keywords = metadata.get('required_transition_keywords', [])

    # ================================================================
    # 1. Read Task Result JSON
    # ================================================================
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 2. Verify File Existence and Timestamps (20 pts)
    # ================================================================
    eddx_ok = task_result.get("eddx_exists") and task_result.get("eddx_created_during_task") and task_result.get("eddx_size_bytes", 0) > 2000
    png_ok = task_result.get("png_exists") and task_result.get("png_created_during_task") and task_result.get("png_size_bytes", 0) > 5000

    if eddx_ok:
        score += 10
        feedback_parts.append("EDDX file created successfully")
    else:
        feedback_parts.append("EDDX file missing or invalid")

    if png_ok:
        score += 10
        feedback_parts.append("PNG export created successfully")
    else:
        feedback_parts.append("PNG export missing or invalid")

    # ================================================================
    # 3. Content Analysis of .eddx File (45 pts)
    # ================================================================
    content_score = 0
    found_states = []
    found_keywords = []
    
    if eddx_ok:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(metadata['expected_eddx'], temp_eddx.name)
            
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                # EdrawMax files store page data in XML files, typically under pages/ or simply in root
                file_list = zf.namelist()
                all_xml_content = ""
                
                for filename in file_list:
                    if filename.endswith(".xml"):
                        try:
                            content = zf.read(filename).decode('utf-8', errors='ignore')
                            all_xml_content += content
                        except Exception:
                            continue
                
                # Check for Required States (25 pts)
                # Max 25 pts, roughly 2.7 pts per state
                for state in required_states:
                    if state.lower() in all_xml_content.lower():
                        found_states.append(state)
                
                state_points = min(25, int(len(found_states) * (25 / len(required_states))))
                content_score += state_points
                feedback_parts.append(f"Found {len(found_states)}/{len(required_states)} states")
                
                # Check for Transition Keywords (20 pts)
                for kw in required_keywords:
                    if kw.lower() in all_xml_content.lower():
                        found_keywords.append(kw)
                
                keyword_points = min(20, int(len(found_keywords) * (20 / len(required_keywords))))
                content_score += keyword_points
                feedback_parts.append(f"Found {len(found_keywords)}/{len(required_keywords)} transition labels")
                
                # Check shape/connector counts roughly (presence check)
                # Simple heuristic: count specific XML tags if possible, or assume content check is enough
                
        except Exception as e:
            feedback_parts.append(f"Error parsing .eddx file: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    score += content_score

    # ================================================================
    # 4. VLM Verification (35 pts)
    # ================================================================
    # We use VLM to verify the diagram structure and workflow, which catches
    # cases where an agent might just type text into a list instead of drawing a diagram.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        frames.append(final_img)

    vlm_prompt = """
    You are verifying an EdrawMax task where the user must create a UML State Machine Diagram for an e-commerce order system.
    
    Please analyze the images (screenshot trajectory) and determine:
    1. Is a diagram visible in the workspace?
    2. Does it look like a State Machine Diagram? (Look for rounded rectangles for states, arrows for transitions, black circle for start, bullseye for end).
    3. Can you see standard order states like "New Order", "Shipped", "Delivered"?
    4. Is the diagram visually organized (not just a pile of shapes)?
    
    Respond in JSON format:
    {
        "diagram_visible": true/false,
        "is_state_machine": true/false,
        "states_readable": true/false,
        "is_organized": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    vlm_score = 0
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('diagram_visible'): vlm_score += 10
        if parsed.get('is_state_machine'): vlm_score += 10
        if parsed.get('states_readable'): vlm_score += 10
        if parsed.get('is_organized'): vlm_score += 5
        
        feedback_parts.append(f"VLM verification confidence: {parsed.get('confidence')}")
    else:
        feedback_parts.append("VLM verification failed to execute")
        
    score += vlm_score

    # ================================================================
    # Final Scoring
    # ================================================================
    
    # Pass threshold: 60 points, AND the file must exist and contain at least some states
    passed = score >= 60 and eddx_ok and len(found_states) >= 4

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }