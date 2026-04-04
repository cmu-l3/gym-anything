#!/usr/bin/env python3
"""
Verifier for create_wireframe_mockup task.

Verifies:
1.  Existence and validity of .eddx and .png files.
2.  Creation timestamps (anti-gaming).
3.  Content of the wireframe using VLM on the exported PNG (or fallback to screenshot).
    - Checks for specific UI elements: Header, Login fields, Buttons.
    - Checks for specific text: "HealthConnect".
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_wireframe_mockup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criteria 1: EDDX File Verification (20 pts) ---
    eddx_exists = result.get("eddx_exists", False)
    eddx_fresh = result.get("eddx_created_during_task", False)
    eddx_size = result.get("eddx_size_bytes", 0)

    if eddx_exists and eddx_size > 5000: # 5KB min for real diagram
        if eddx_fresh:
            score += 20
            feedback_parts.append("Valid .eddx file created.")
        else:
            score += 5
            feedback_parts.append("File .eddx exists but timestamp is old (reused file?).")
    elif eddx_exists:
        feedback_parts.append("File .eddx created but too small (likely empty).")
    else:
        feedback_parts.append("File .eddx not found.")

    # --- Criteria 2: PNG Export Verification (10 pts) ---
    png_exists = result.get("png_exists", False)
    png_fresh = result.get("png_created_during_task", False)
    png_size = result.get("png_size_bytes", 0)
    
    png_path_local = None

    if png_exists and png_size > 5000:
        if png_fresh:
            score += 10
            feedback_parts.append("Valid .png export created.")
            
            # Copy PNG for VLM analysis
            try:
                temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                copy_from_env(result["png_path"], temp_png.name)
                png_path_local = temp_png.name
            except Exception as e:
                logger.error(f"Failed to copy PNG for VLM: {e}")
        else:
            feedback_parts.append("File .png exists but timestamp is old.")
    else:
        feedback_parts.append("File .png not found or empty.")

    # --- Criteria 3: VLM Content Verification (70 pts) ---
    
    # Select image for VLM: preferred exported PNG, fallback to final screenshot
    image_to_analyze = png_path_local
    source_type = "exported PNG"
    
    if not image_to_analyze:
        # Fallback to framework's final screenshot if export failed
        image_to_analyze = get_final_screenshot(traj)
        source_type = "final screenshot"
        feedback_parts.append("Using final screenshot for verification (PNG export missing).")
    
    if image_to_analyze:
        prompt = """
        Analyze this UI wireframe image for a patient portal login page.
        Check for the presence of the following specific elements:
        1. HEADER: Text "HealthConnect" or "HealthConnect Patient Portal".
        2. INPUT: A field labeled "Username" or "Email".
        3. INPUT: A field labeled "Password".
        4. BUTTON: A primary button labeled "Sign In", "Login", or similar.
        5. CHECKBOX: A checkbox labeled "Remember Me".
        6. LINK: A text link for "Forgot Password?".
        7. FOOTER: Copyright text or footer area.

        Return a JSON object with boolean keys:
        {
            "header_found": true/false,
            "username_field_found": true/false,
            "password_field_found": true/false,
            "signin_button_found": true/false,
            "remember_checkbox_found": true/false,
            "forgot_link_found": true/false,
            "footer_found": true/false,
            "overall_layout_quality": "good/poor"
        }
        """
        
        vlm_resp = query_vlm(prompt=prompt, image=image_to_analyze)
        
        if vlm_resp and vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            
            # Header (10 pts)
            if parsed.get("header_found"):
                score += 10
                feedback_parts.append("Header found.")
            
            # Form Fields (20 pts - 10 each)
            if parsed.get("username_field_found"):
                score += 10
            if parsed.get("password_field_found"):
                score += 10
            if parsed.get("username_field_found") and parsed.get("password_field_found"):
                feedback_parts.append("Login fields found.")
            
            # Button (10 pts)
            if parsed.get("signin_button_found"):
                score += 10
                feedback_parts.append("Sign In button found.")
            
            # Secondary Elements (20 pts total)
            secondary_score = 0
            if parsed.get("remember_checkbox_found"): secondary_score += 7
            if parsed.get("forgot_link_found"): secondary_score += 7
            if parsed.get("footer_found"): secondary_score += 6
            score += min(20, secondary_score) # Cap at 20
            if secondary_score > 0:
                feedback_parts.append(f"Secondary elements found ({secondary_score} pts).")

            # Layout (10 pts)
            if parsed.get("overall_layout_quality") == "good":
                score += 10
                feedback_parts.append("Layout is coherent.")

        else:
            feedback_parts.append("VLM analysis failed.")
            
        # Cleanup local temp png
        if png_path_local and os.path.exists(png_path_local):
            os.unlink(png_path_local)
    else:
        feedback_parts.append("No image available for VLM verification.")

    # Final Pass/Fail
    passed = score >= 60 and eddx_exists and eddx_fresh
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }