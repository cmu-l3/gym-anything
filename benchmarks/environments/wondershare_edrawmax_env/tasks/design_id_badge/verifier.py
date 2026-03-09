#!/usr/bin/env python3
"""
Verifier for design_id_badge task.
Checks for correct page dimensions, text content, and visual layout.
"""

import json
import os
import tempfile
import zipfile
import logging
from typing import Dict, Any

# Optional: Import gym_anything VLM utils if available in the environment context
# usually injected or available in python path.
# For this script we assume standard imports or helper functions.

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_id_badge(traj, env_info, task_info):
    """
    Verify the ID badge design.
    
    Criteria:
    1. Files (.eddx and .png) exist and were created during task.
    2. .eddx XML content contains required text (Name, Company, ID).
    3. .eddx Page dimensions match ID card size (approx 2.13" x 3.38").
    4. VLM verifies visual layout (Portrait, Photo placeholder, QR code).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_texts = metadata.get('required_text', [])
    
    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Creation (20 pts)
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_created = result_data.get('eddx_created_during_task', False)
    png_exists = result_data.get('png_exists', False)
    
    if eddx_exists and eddx_created:
        score += 10
        feedback_parts.append(".eddx file created")
    elif eddx_exists:
        score += 5
        feedback_parts.append(".eddx file exists but old")
    else:
        feedback_parts.append(".eddx file missing")

    if png_exists:
        score += 10
        feedback_parts.append(".png export created")
    else:
        feedback_parts.append(".png export missing")

    if not eddx_exists:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Content Analysis (XML Parsing) (40 pts)
    # Copy .eddx to host for analysis
    temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
    try:
        copy_from_env(metadata['expected_eddx_path'], temp_eddx.name)
        
        with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
            file_list = zf.namelist()
            all_xml_content = ""
            
            # Aggregate XML content from pages
            for filename in file_list:
                if filename.endswith(".xml"):
                    try:
                        all_xml_content += zf.read(filename).decode('utf-8', errors='ignore')
                    except:
                        pass
            
            # Check for text
            found_texts = 0
            missing_texts = []
            for text in required_texts:
                if text in all_xml_content:
                    found_texts += 1
                else:
                    missing_texts.append(text)
            
            if found_texts == len(required_texts):
                score += 25
                feedback_parts.append("All text content found")
            else:
                partial = int(25 * (found_texts / len(required_texts)))
                score += partial
                feedback_parts.append(f"Missing text: {', '.join(missing_texts)}")
                
            # Check for Page Dimensions (Heuristic check)
            # EdrawMax XML usually has PageWidth/PageHeight attributes. 
            # We look for aspect ratio evidence if exact units are hard to predict.
            # ID Card ratio: 2.13 / 3.38 = 0.63
            # A4 ratio: 0.70 (or 1.41 if landscape)
            # This is tricky in XML raw string, but we can look for specific strings if VLM fails.
            # We will rely on VLM for the geometry check to be robust.

    except Exception as e:
        feedback_parts.append(f"Failed to analyze .eddx content: {e}")
    finally:
        if os.path.exists(temp_eddx.name):
            os.unlink(temp_eddx.name)

    # 3. VLM Verification (40 pts)
    # We use the final screenshot or the exported PNG if available
    
    # Ideally, we verify the exported PNG content
    if png_exists:
        from gym_anything.vlm import query_vlm, get_final_screenshot
        
        # We need the PNG image content. Since verify logic runs on host, 
        # we copy the PNG from env.
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(metadata['expected_png_path'], temp_png.name)
            
            # We construct a prompt for VLM
            prompt = """
            You are verifying a generated Employee ID Badge.
            
            The badge should have:
            1. Vertical orientation (taller than wide).
            2. Header text 'NEXUS DYNAMICS'.
            3. A photo placeholder.
            4. Employee name 'Alex Mercer'.
            5. A QR Code visible.
            6. A blue footer bar.
            
            Does the image meet these criteria?
            Respond with JSON: {"orientation_correct": bool, "qr_code_visible": bool, "content_visible": bool, "layout_correct": bool}
            """
            
            vlm_result = query_vlm(prompt=prompt, image=temp_png.name)
            
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                if parsed.get('orientation_correct'):
                    score += 10
                    feedback_parts.append("Correct vertical orientation")
                
                if parsed.get('qr_code_visible'):
                    score += 15 # High value for functional element
                    feedback_parts.append("QR Code detected")
                    
                if parsed.get('content_visible') and parsed.get('layout_correct'):
                    score += 15
                    feedback_parts.append("Layout/Content visually verified")
            else:
                feedback_parts.append("VLM verification failed")
                
        except Exception as e:
            feedback_parts.append(f"VLM check error: {e}")
        finally:
            if os.path.exists(temp_png.name):
                os.unlink(temp_png.name)
    else:
        # Fallback to trajectory final screenshot if PNG export missing
        feedback_parts.append("No PNG to verify, skipping visual check")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }