#!/usr/bin/env python3
"""
Verifier for create_metro_map_transit_plan task.

Verification Strategy:
1. File Verification: Check existence and timestamp of .eddx and .png files.
2. Content Verification: Unzip .eddx (which is XML-based) and check for required station names and title.
3. VLM Verification: Use trajectory frames to confirm metro map visual style and workflow.
"""

import os
import json
import zipfile
import tempfile
import logging
import shutil
from vlm_utils import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_metro_map(traj, env_info, task_info):
    """
    Verify the creation of the Boston metro map.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/task_result.json", temp_result)
        with open(temp_result, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result):
            os.unlink(temp_result)

    # 2. Check File Existence & Timestamps (30 points)
    eddx_ok = result_data.get("eddx_exists") and result_data.get("eddx_created_during_task") and result_data.get("eddx_size", 0) > 2000
    png_ok = result_data.get("png_exists") and result_data.get("png_created_during_task") and result_data.get("png_size", 0) > 10000

    if eddx_ok:
        score += 15
        feedback_parts.append("EdrawMax file created successfully.")
    else:
        feedback_parts.append("EdrawMax (.eddx) file missing or invalid.")

    if png_ok:
        score += 15
        feedback_parts.append("PNG export created successfully.")
    else:
        feedback_parts.append("PNG export missing or too small.")

    # 3. Content Analysis of .eddx (40 points)
    # .eddx files are ZIP archives containing XML. We search the XML for text labels.
    content_score = 0
    missing_terms = []
    
    if eddx_ok:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx').name
        try:
            copy_from_env("/home/ga/Documents/boston_metro_map.eddx", temp_eddx)
            
            text_content = ""
            with zipfile.ZipFile(temp_eddx, 'r') as z:
                for filename in z.namelist():
                    if filename.endswith('.xml'):
                        try:
                            text_content += z.read(filename).decode('utf-8', errors='ignore')
                        except:
                            pass
            
            # Check for required strings
            found_count = 0
            for term in required_strings:
                if term.lower() in text_content.lower():
                    found_count += 1
                else:
                    missing_terms.append(term)
            
            # Calculate score based on found terms
            # 7 terms total -> ~5.7 points per term
            if len(required_strings) > 0:
                content_score = int((found_count / len(required_strings)) * 40)
            
            score += content_score
            
            if len(missing_terms) == 0:
                feedback_parts.append("All stations and titles found in document.")
            else:
                feedback_parts.append(f"Missing text in document: {', '.join(missing_terms)}")
                
        except zipfile.BadZipFile:
            feedback_parts.append("File is not a valid EdrawMax archive.")
        except Exception as e:
            feedback_parts.append(f"Error analyzing file content: {str(e)}")
        finally:
            if os.path.exists(temp_eddx):
                os.unlink(temp_eddx)
    else:
        feedback_parts.append("Skipping content analysis (file missing).")

    # 4. VLM Verification (30 points)
    # Use trajectory to confirm it's a metro map and workflow was followed
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        # Add final shot to frames if it exists
        if final_shot:
            frames.append(final_shot)
            
        if frames:
            prompt = """
            You are verifying an EdrawMax task. The user was supposed to create a Metro/Transit Map.
            
            Look at the screenshots and answer:
            1. Do you see a diagram that looks like a metro/subway map (thick colored lines, 45-degree angles, station dots)?
            2. Are there at least two distinct lines (one Blue, one Silver/Gray)?
            3. Do the lines intersect or meet at a station?
            4. Is there a title "Airport Transit Expansion Proposal" or similar?
            
            Return JSON:
            {
                "looks_like_metro_map": true/false,
                "has_two_colored_lines": true/false,
                "lines_intersect": true/false,
                "title_visible": true/false,
                "confidence": "high/medium/low"
            }
            """
            
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                
                if parsed.get('looks_like_metro_map'): vlm_score += 10
                if parsed.get('has_two_colored_lines'): vlm_score += 10
                if parsed.get('lines_intersect'): vlm_score += 5
                if parsed.get('title_visible'): vlm_score += 5
                
                feedback_parts.append(f"VLM Visual Check: {vlm_score}/30 points.")
            else:
                feedback_parts.append("VLM analysis failed.")
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append("VLM check encountered an error.")

    score += vlm_score
    
    # Final cleanup
    score = min(100, score) # Cap at 100
    
    # Pass threshold: Need files + decent content + visual confirmation
    # If they have files (30) + half content (20) + some visual (10) = 60
    passed = score >= 60 and eddx_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }