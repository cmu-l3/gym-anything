#!/usr/bin/env python3
"""
Verifier for create_bpmn_diagram task.

Evaluates the agent's performance based on:
1. Creation of the .eddx diagram file (checks content for keywords).
2. Creation of the .png export file (checks validity and size).
3. VLM verification of the visual workflow and final output.
"""

import json
import os
import tempfile
import zipfile
import logging
from typing import Dict, Any, List

# VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bpmn_diagram(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies the BPMN diagram creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load basic result metadata
    task_result = {}
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. Check File Existence & Creation (30 points)
    eddx_exists = task_result.get('eddx_exists', False)
    eddx_created = task_result.get('eddx_created_during_task', False)
    png_exists = task_result.get('png_exists', False)
    png_created = task_result.get('png_created_during_task', False)
    
    if eddx_exists and eddx_created:
        score += 15
        feedback_parts.append("EDDX file created successfully.")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but modification time is old.")
    else:
        feedback_parts.append("EDDX file not found.")

    if png_exists and png_created:
        score += 15
        feedback_parts.append("PNG export created successfully.")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG file exists but modification time is old.")
    else:
        feedback_parts.append("PNG export not found.")

    # 3. Analyze EDDX Content (40 points)
    # .eddx files are ZIP archives containing XML data. We search for required text labels.
    content_score = 0
    found_keywords = []
    missing_keywords = []
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(metadata['eddx_path'], temp_eddx.name)
            
            # EdrawMax files (.eddx) are zip files. Text is usually in .xml files inside.
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                all_text = ""
                for filename in zf.namelist():
                    if filename.endswith('.xml'):
                        try:
                            data = zf.read(filename).decode('utf-8', errors='ignore')
                            all_text += data
                        except:
                            pass
                
                # Check for keywords
                # We normalize slightly by ignoring case for robust checking
                all_text_lower = all_text.lower()
                
                for keyword in required_text:
                    if keyword.lower() in all_text_lower:
                        found_keywords.append(keyword)
                    else:
                        missing_keywords.append(keyword)
                
                # Calculation: 40 points total. Proportional to found keywords.
                if required_text:
                    content_score = int(40 * (len(found_keywords) / len(required_text)))
                else:
                    content_score = 40 # If no text required, give full points for content if file exists
                    
                score += content_score
                
                if len(missing_keywords) == 0:
                    feedback_parts.append("All required diagram labels found.")
                elif len(found_keywords) > 0:
                    feedback_parts.append(f"Found {len(found_keywords)}/{len(required_text)} required labels.")
                else:
                    feedback_parts.append("Diagram appears empty or text not found.")

        except zipfile.BadZipFile:
            feedback_parts.append("EDDX file is not a valid zip archive.")
        except Exception as e:
            feedback_parts.append(f"Error analyzing EDDX content: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # 4. VLM Verification (30 points)
    # We verify the visual structure using trajectory frames and the exported PNG (if available).
    vlm_score = 0
    
    if VLM_AVAILABLE:
        # Prepare images
        images_to_check = []
        
        # Add trajectory frames
        traj_frames = sample_trajectory_frames(traj, n=3)
        images_to_check.extend(traj_frames)
        
        # Add final screenshot
        final_ss = get_final_screenshot(traj)
        if final_ss:
            images_to_check.append(final_ss)
            
        # Add exported PNG if possible (would need to read it back, but let's stick to system screenshots for safety)
        # Note: If we really wanted to check the PNG content, we could read it here. 
        # For now, checking the screen during work is sufficient validation of "work done".
        
        prompt = """
        You are verifying an agent's work in creating a BPMN diagram in EdrawMax.
        
        Look for the following visual elements in the sequence of images:
        1. **Pools and Lanes**: Are there rectangular containers labeled "Customer" or "Order Fulfillment"?
        2. **BPMN Shapes**: Do you see specific BPMN symbols like Start Events (circles), Tasks (rounded rectangles), Gateways (diamonds)?
        3. **Structure**: Is there a flowchart-like structure with arrows connecting shapes?
        4. **Complexity**: Does the diagram look like a "Order Fulfillment" process (multiple steps, branching)?
        
        Answer with a JSON object:
        {
            "pools_visible": boolean,
            "bpmn_shapes_visible": boolean,
            "diagram_complexity_sufficient": boolean,
            "confidence": float (0.0 to 1.0)
        }
        """
        
        try:
            result = query_vlm(images=images_to_check, prompt=prompt)
            if result and result.get('success'):
                parsed = result.get('parsed', {})
                
                # Scoring criteria
                if parsed.get('pools_visible'): vlm_score += 10
                if parsed.get('bpmn_shapes_visible'): vlm_score += 10
                if parsed.get('diagram_complexity_sufficient'): vlm_score += 10
                
                feedback_parts.append(f"Visual verification score: {vlm_score}/30")
            else:
                # Fallback if VLM fails: give partial credit if file content was good
                if content_score > 20:
                    vlm_score = 15
                    feedback_parts.append("VLM check skipped, awarding partial visual credit based on content.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            if content_score > 20:
                vlm_score = 15
    
    score += vlm_score

    # Final Pass/Fail logic
    # Pass if files exist (30pts) AND significant content found (>50% keywords)
    pass_threshold = 60
    passed = score >= pass_threshold and eddx_exists and len(found_keywords) >= (len(required_text) / 2)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }