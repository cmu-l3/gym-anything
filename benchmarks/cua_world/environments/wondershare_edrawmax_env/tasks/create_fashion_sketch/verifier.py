#!/usr/bin/env python3
"""
Verifier for create_fashion_sketch task.
"""
import os
import json
import tempfile
import zipfile
import logging
import shutil
from vlm_utils import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_fashion_sketch(traj, env_info, task_info):
    """
    Verifies the fashion sketch task:
    1. Files (.eddx, .png) exist and were created during task.
    2. .eddx content contains specific text labels (XML parsing).
    3. VLM verifies the visual appearance (Shirt, Colors, Layout).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', [])
    min_size = metadata.get('min_file_size_kb', 5) * 1024

    score = 0
    feedback_parts = []
    
    # --- Step 1: Get Result JSON ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    eddx_info = result_data.get('eddx_file', {})
    png_info = result_data.get('png_file', {})

    # --- Criterion 1: Files Exist & Timestamps (30 pts) ---
    files_ok = False
    if eddx_info.get('exists') and eddx_info.get('created_during'):
        if eddx_info.get('size') > min_size:
            score += 15
            feedback_parts.append("EDDX file created successfully.")
            files_ok = True
        else:
            feedback_parts.append("EDDX file is too small (likely empty).")
    else:
        feedback_parts.append("EDDX file missing or not created during task.")

    if png_info.get('exists') and png_info.get('created_during'):
        if png_info.get('size') > 1024: # >1KB
            score += 15
            feedback_parts.append("PNG export created successfully.")
        else:
            feedback_parts.append("PNG file too small.")
    else:
        feedback_parts.append("PNG export missing.")

    # --- Criterion 2: Content Analysis (Text in XML) (40 pts) ---
    # We only check content if file exists
    content_score = 0
    if files_ok:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/uniform_spec.eddx", temp_eddx.name)
            
            found_labels = []
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                # Concatenate all XML content
                all_xml = ""
                for name in zf.namelist():
                    if name.endswith(".xml"):
                        try:
                            all_xml += zf.read(name).decode("utf-8", errors="ignore")
                        except:
                            pass
                
                # Check for required strings
                for txt in required_text:
                    # Case insensitive search
                    if txt.lower() in all_xml.lower():
                        found_labels.append(txt)
            
            # Scoring for text
            # 4 items * 10 pts each = 40 pts
            for _ in found_labels:
                content_score += 10
            
            if len(found_labels) == len(required_text):
                feedback_parts.append("All text labels found in document.")
            else:
                feedback_parts.append(f"Found labels: {found_labels}. Missing some required text.")
                
        except zipfile.BadZipFile:
            feedback_parts.append("EDDX file is corrupted or not a valid archive.")
        except Exception as e:
            feedback_parts.append(f"Error analyzing file content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    score += content_score

    # --- Criterion 3: VLM Verification (Visuals) (30 pts) ---
    # We check if it looks like a shirt with the right colors
    vlm_score = 0
    try:
        # Use trajectory to see work being done, or final screenshot if available
        frames = sample_trajectory_frames(traj, n=3)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
        
        if frames:
            prompt = """
            You are verifying a task to design a fashion flat sketch in EdrawMax.
            The user was asked to:
            1. Draw a Polo Shirt or T-Shirt (Navy Blue).
            2. Add a Pocket (Dark/Black).
            3. Add a Logo Badge (Yellow).
            4. Add annotations/callouts.

            Look at the screenshots. 
            - Do you see a shirt shape?
            - Is the shirt blue?
            - Is there a yellow badge or logo element?
            - Are there text annotations pointing to the shirt?

            Reply JSON:
            {
                "shirt_visible": true/false,
                "shirt_color_blue": true/false,
                "badge_visible": true/false,
                "annotations_visible": true/false
            }
            """
            
            result = query_vlm(images=frames, prompt=prompt)
            if result and result.get('success'):
                parsed = result.get('parsed', {})
                if parsed.get('shirt_visible'): vlm_score += 10
                if parsed.get('shirt_color_blue'): vlm_score += 10
                if parsed.get('badge_visible') or parsed.get('annotations_visible'): vlm_score += 10
                feedback_parts.append(f"VLM Analysis: {parsed}")
            else:
                feedback_parts.append("VLM verification failed or inconclusive.")
                # Fallback: if text analysis was perfect, give partial VLM points
                if content_score >= 30:
                    vlm_score += 15 
    except Exception as e:
        logger.error(f"VLM error: {e}")
        # Graceful degradation if VLM fails
        if content_score >= 30:
            vlm_score += 15

    score += vlm_score

    # Final tally
    passed = (score >= 70) and files_ok
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }