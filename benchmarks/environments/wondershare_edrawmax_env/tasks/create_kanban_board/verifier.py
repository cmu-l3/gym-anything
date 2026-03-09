#!/usr/bin/env python3
"""
Verifier for create_kanban_board task.

Verification Strategy:
1. File Verification (20 pts): Check existence and timestamps of .eddx and .png files.
2. Content Verification (40 pts): Unzip .eddx and check XML for required strings (headers, task names).
3. Visual Verification (40 pts): Use VLM to verify structure (columns) and attributes (colors, placement).
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_kanban_board(traj, env_info, task_info):
    """
    Verify the Kanban board creation task using file analysis and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', [])
    
    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. File Artifact Verification (20 pts)
    # ------------------------------------------------------------------
    # Retrieve result JSON from export_result.sh
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    eddx_exists = result_data.get('eddx_exists', False)
    eddx_fresh = result_data.get('eddx_created_during_task', False)
    png_exists = result_data.get('png_exists', False)
    png_fresh = result_data.get('png_created_during_task', False)

    if eddx_exists and eddx_fresh:
        score += 10
        feedback_parts.append("EDDX file created successfully.")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but timestamp is old.")
    else:
        feedback_parts.append("EDDX file missing.")

    if png_exists and png_fresh:
        score += 10
        feedback_parts.append("PNG export created successfully.")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG file exists but timestamp is old.")
    else:
        feedback_parts.append("PNG export missing.")

    # ------------------------------------------------------------------
    # 2. Content Verification (Zip/XML Analysis) (40 pts)
    # ------------------------------------------------------------------
    content_score = 0
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/sprint_board.eddx", temp_eddx.name)
            
            # EdrawMax .eddx files are zip archives containing page XMLs
            if zipfile.is_zipfile(temp_eddx.name):
                found_strings = 0
                all_text_content = ""
                
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    for filename in zf.namelist():
                        if filename.endswith('.xml'):
                            try:
                                content = zf.read(filename).decode('utf-8', errors='ignore')
                                all_text_content += content
                            except:
                                pass
                
                # Check for required strings in the XML content
                missing_strings = []
                for s in required_strings:
                    if s.lower() in all_text_content.lower():
                        found_strings += 1
                    else:
                        missing_strings.append(s)
                
                # Calculate content score based on percentage of strings found
                if len(required_strings) > 0:
                    content_score = int((found_strings / len(required_strings)) * 40)
                
                score += content_score
                if content_score == 40:
                    feedback_parts.append("All text content found in diagram file.")
                else:
                    feedback_parts.append(f"Found {found_strings}/{len(required_strings)} required text elements. Missing: {', '.join(missing_strings)}")
            else:
                feedback_parts.append("EDDX file is not a valid zip archive.")
                
        except Exception as e:
            feedback_parts.append(f"Failed to analyze EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    else:
        feedback_parts.append("Skipping content analysis (EDDX missing).")

    # ------------------------------------------------------------------
    # 3. VLM Visual Verification (40 pts)
    # ------------------------------------------------------------------
    # We use trajectory frames + final screenshot to verify:
    # 1. Structure (4 columns)
    # 2. Colors (Red/Green/Blue cards)
    # 3. Placement (Logic)
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        frames.append(final_img)
    
    if frames:
        vlm_prompt = """
        You are verifying a Kanban board created in EdrawMax.
        
        The board should have:
        1. Title: "Sprint 24 - Inventory Migration"
        2. 4 Columns labeled: "Backlog", "In Progress", "Code Review", "Done"
        3. Task cards with specific colors:
           - "Fix Null Pointer Exception" should be RED.
           - "Legacy DB Backup" should be GREEN.
           - Others should be BLUE.
        
        Look at the provided screenshots.
        Q1: Do you see a Kanban board with 4 distinct columns?
        Q2: Are the headers "Backlog", "In Progress", "Code Review", "Done" visible?
        Q3: Is there a RED card visible in the "Code Review" column (or 3rd column)?
        Q4: Is there a GREEN card visible in the "Done" column (or 4th column)?
        
        Respond with JSON:
        {
            "columns_visible": true/false,
            "headers_correct": true/false,
            "red_bug_card_visible": true/false,
            "green_done_card_visible": true/false,
            "overall_quality": "low/medium/high"
        }
        """
        
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                vlm_score = 0
                
                if parsed.get('columns_visible', False):
                    vlm_score += 10
                if parsed.get('headers_correct', False):
                    vlm_score += 10
                if parsed.get('red_bug_card_visible', False):
                    vlm_score += 10
                if parsed.get('green_done_card_visible', False):
                    vlm_score += 10
                    
                score += vlm_score
                feedback_parts.append(f"Visual verification score: {vlm_score}/40")
                
            else:
                feedback_parts.append("VLM verification failed to execute.")
        except Exception as e:
            feedback_parts.append(f"VLM error: {e}")
    else:
        feedback_parts.append("No screenshots available for visual verification.")

    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    # Pass if score >= 70 AND essential files exist
    passed = (score >= 70) and eddx_exists and png_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }