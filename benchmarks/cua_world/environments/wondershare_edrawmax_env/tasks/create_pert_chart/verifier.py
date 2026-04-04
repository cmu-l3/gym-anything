#!/usr/bin/env python3
"""
Verifier for create_pert_chart task.

Verification Strategy:
1. File Verification (40 pts):
   - Check if .eddx file exists and was created during task.
   - Check if .png file exists and was created during task.
   - Check file sizes to ensure they aren't empty.

2. Content Verification (30 pts):
   - Unzip the .eddx file (it's a ZIP archive).
   - Scan XML content for specific activity names (e.g., "Requirements Gathering", "Go-Live").
   - Check for title text.

3. VLM Verification (30 pts):
   - Analyze trajectory frames to confirm a network diagram was built (nodes + arrows).
   - Analyze final screenshot/PNG to verify visual structure (left-to-right flow, dependencies).
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_pert_chart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_activities = metadata.get('required_activities', [])
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Result JSON
    # =========================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # =========================================================
    # 2. File Verification (40 points)
    # =========================================================
    eddx_exists = result.get('eddx_exists', False)
    eddx_created = result.get('eddx_created_during_task', False)
    eddx_size = result.get('eddx_size', 0)
    
    png_exists = result.get('png_exists', False)
    png_created = result.get('png_created_during_task', False)
    png_size = result.get('png_size', 0)

    # EDDX checks (25 pts)
    if eddx_exists and eddx_created and eddx_size > 5000:
        score += 25
        feedback_parts.append("Valid source file (.eddx) created.")
    elif eddx_exists:
        score += 10
        feedback_parts.append("Source file exists but timestamp/size check warning.")
    else:
        feedback_parts.append("Source file (.eddx) missing.")

    # PNG checks (15 pts)
    if png_exists and png_created and png_size > 10000:
        score += 15
        feedback_parts.append("Valid export image (.png) created.")
    elif png_exists:
        score += 5
        feedback_parts.append("Export image exists but timestamp/size check warning.")
    else:
        feedback_parts.append("Export image (.png) missing.")

    # =========================================================
    # 3. Content Verification (30 points)
    # =========================================================
    # We need to analyze the actual EDDX file content to find activity names
    content_score = 0
    found_activities = []
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            # Copy EDDX from container
            copy_from_env("/home/ga/Diagrams/pert_migration.eddx", temp_eddx.name)
            
            # Unzip and search XML
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Collect all XML text
                    all_text = ""
                    for name in zf.namelist():
                        if name.endswith('.xml'):
                            try:
                                all_text += zf.read(name).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Search for activity names
                    matches = 0
                    for act in required_activities:
                        if act in all_text:
                            matches += 1
                            found_activities.append(act)
                    
                    # Search for title
                    if "PERT" in all_text or "Migration" in all_text:
                        content_score += 5
                        feedback_parts.append("Title text found.")
                    
                    # Score based on matches (Max 25 for activities)
                    # 10 activities total. 2.5 pts each.
                    act_score = min(25, matches * 2.5)
                    content_score += act_score
                    feedback_parts.append(f"Found {matches}/10 required activities in diagram.")
            else:
                feedback_parts.append("EDDX file is not a valid zip archive.")

        except Exception as e:
            feedback_parts.append(f"Content check failed: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    score += int(content_score)

    # =========================================================
    # 4. VLM Verification (30 points)
    # =========================================================
    # Use trajectory frames to confirm it's a network diagram, not just a list
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an agent's work in EdrawMax. 
    The task was to create a PERT Chart (Network Diagram) for a project.
    
    Look at the provided screenshots.
    1. Do you see a diagram composed of nodes (shapes) connected by directional arrows?
    2. Is the layout generally a network flow (e.g. left-to-right or branching), NOT just a vertical list or spreadsheet?
    3. Can you see text labels inside the shapes that look like project tasks (e.g., "Requirements", "Analysis", "Testing")?
    4. Are there numbers visible in or near the nodes (representing time estimates)?
    
    Respond in JSON:
    {
        "is_network_diagram": true/false,
        "has_text_labels": true/false,
        "has_numbers": true/false,
        "structure_quality": "high/medium/low/none",
        "reasoning": "..."
    }
    """
    
    vlm_score = 0
    try:
        # We use the final screen + frames to give context
        images_to_check = frames + [final_screen] if final_screen else frames
        
        if images_to_check:
            result = query_vlm(
                prompt=vlm_prompt,
                images=images_to_check
            )
            
            parsed = result.get('parsed', {})
            if parsed.get('is_network_diagram'):
                vlm_score += 15
            if parsed.get('has_text_labels'):
                vlm_score += 10
            if parsed.get('has_numbers'):
                vlm_score += 5
                
            feedback_parts.append(f"VLM Analysis: {parsed.get('reasoning', 'No reasoning provided')}")
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # Fallback: if we have high content score, give partial VLM points
        if content_score > 20:
            vlm_score += 15
            feedback_parts.append("VLM failed, awarded partial points based on content.")

    score += vlm_score

    # =========================================================
    # Final Result
    # =========================================================
    passed = score >= 60 and eddx_exists and eddx_created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }