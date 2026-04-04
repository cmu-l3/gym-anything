#!/usr/bin/env python3
"""
Verifier for create_fishbone_diagram task.

Combines:
1. File-based verification: Checks if .eddx and .png exist and were created during the task.
2. Content verification: Unzips the .eddx file (which is XML based) and searches for required strings.
3. VLM verification: Checks visual structure using trajectory and final screenshot.
"""

import os
import json
import tempfile
import zipfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# List of text strings expected in the diagram
REQUIRED_STRINGS = [
    # Effect
    "Online Banking System Outage",
    # Categories
    "People", "Process", "Technology", "Environment", "Management", "Measurement",
    # Sample Sub-causes (at least some of these should be present)
    "Insufficient on-call staffing",
    "No rollback procedure documented",
    "Database connection pool exhausted",
    "Data center cooling failure",
    "Incident response budget",
    "SLA breach detection"
]

def verify_create_fishbone_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Result JSON
    # ------------------------------------------------------------------
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ------------------------------------------------------------------
    # 2. File Existence & Timestamp Checks (30 points)
    # ------------------------------------------------------------------
    
    # EDDX Check
    eddx_exists = result_data.get("eddx_exists", False)
    eddx_fresh = result_data.get("eddx_created_during_task", False)
    eddx_size = result_data.get("eddx_size_bytes", 0)

    if eddx_exists and eddx_size > 1000: # Minimal valid EDDX size
        if eddx_fresh:
            score += 15
            feedback_parts.append("Valid .eddx file created.")
        else:
            score += 5
            feedback_parts.append(".eddx file exists but timestamp is old (anti-gaming fail).")
    else:
        feedback_parts.append("No valid .eddx file found.")

    # PNG Check
    png_exists = result_data.get("png_exists", False)
    png_fresh = result_data.get("png_created_during_task", False)
    png_size = result_data.get("png_size_bytes", 0)

    if png_exists and png_size > 1000:
        if png_fresh:
            score += 15
            feedback_parts.append("Valid .png export created.")
        else:
            score += 5
            feedback_parts.append(".png file exists but timestamp is old.")
    else:
        feedback_parts.append("No valid .png export found.")

    # ------------------------------------------------------------------
    # 3. Content Verification (Text in EDDX) (40 points)
    # ------------------------------------------------------------------
    content_score = 0
    found_strings = []
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Diagrams/fishbone_outage_rca.eddx", temp_eddx.name)
            
            # EdrawMax .eddx is a zip. Extract text from XML files.
            text_content = ""
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as z:
                    for filename in z.namelist():
                        if filename.endswith('.xml'):
                            try:
                                text_content += z.read(filename).decode('utf-8', errors='ignore')
                            except:
                                pass
            
            # Check for strings
            # 1. Effect Name (Critical) - 10 pts
            if "Online Banking System Outage" in text_content:
                content_score += 10
                found_strings.append("Effect Name")
            
            # 2. Categories - 2 pts each (max 12 pts)
            cats_found = 0
            for cat in ["People", "Process", "Technology", "Environment", "Management", "Measurement"]:
                if cat in text_content:
                    cats_found += 1
            content_score += (cats_found * 2)
            if cats_found > 0:
                found_strings.append(f"{cats_found}/6 Categories")

            # 3. Sub-causes - 3 pts each for the specific sampled list (max 18 pts)
            sub_causes = [
                "Insufficient on-call staffing", "No rollback procedure documented",
                "Database connection pool exhausted", "Data center cooling failure",
                "Incident response budget", "SLA breach detection"
            ]
            subs_found = 0
            for sub in sub_causes:
                # Flexible matching (case insensitive or partial could be better, but strict is safer for now)
                if sub in text_content:
                    subs_found += 1
            
            content_score += (subs_found * 3)
            if subs_found > 0:
                found_strings.append(f"{subs_found}/{len(sub_causes)} Key Sub-causes")

        except Exception as e:
            feedback_parts.append(f"Content verification failed: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    score += min(content_score, 40) # Cap content score at 40
    if content_score > 0:
        feedback_parts.append(f"Content verified: {', '.join(found_strings)}")

    # ------------------------------------------------------------------
    # 4. VLM Verification (Visual Structure) (30 points)
    # ------------------------------------------------------------------
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        prompt = """
        You are verifying a task to create a Fishbone (Ishikawa) diagram in EdrawMax.
        
        Analyze the images provided (trajectory and final state).
        
        1. **Fishbone Structure**: Do you see a diagram with a central horizontal spine and angled branches coming off it (like a fish skeleton)?
        2. **Complexity**: Does the diagram look like it has text labels on the branches?
        3. **App State**: Is the EdrawMax application visible?
        
        Respond in JSON:
        {
            "fishbone_structure_visible": true/false,
            "text_labels_visible": true/false,
            "edrawmax_visible": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        try:
            result = query_vlm(images=frames + [final_screen], prompt=prompt)
            parsed = result.get('parsed', {})
            
            if parsed.get('edrawmax_visible', False):
                vlm_score += 5
            
            if parsed.get('fishbone_structure_visible', False):
                vlm_score += 15
                feedback_parts.append("VLM confirms Fishbone structure.")
                
            if parsed.get('text_labels_visible', False):
                vlm_score += 10
                
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Fallback: if we found text content and file exists, give partial credit
            if score >= 50: 
                vlm_score += 10
                feedback_parts.append("VLM failed, applied fallback score.")

    score += vlm_score

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = (score >= 60) and eddx_exists and eddx_fresh
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }