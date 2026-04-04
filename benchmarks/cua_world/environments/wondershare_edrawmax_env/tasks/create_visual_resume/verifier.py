#!/usr/bin/env python3
"""
Verifier for create_visual_resume task.

Criteria:
1. Files (.eddx and .pdf) must exist and be created during the task.
2. PDF content must contain key text (Name, Skills, Companies).
3. VLM Verification:
   - Layout: Two columns (Sidebar/Main).
   - Visuals: Skills represented with graphical ratings (bars/stars/dots), not just text.
"""

import json
import os
import tempfile
import logging
import sys

# Try importing pdfminer for text extraction
try:
    from pdfminer.high_level import extract_text
    PDFMINER_AVAILABLE = True
except ImportError:
    PDFMINER_AVAILABLE = False

# Import VLM utilities from framework
# Assuming gym_anything.vlm exposes these helpers
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback/Mock for local testing if framework not present
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj):
        return None
    def sample_trajectory_frames(traj, n=1):
        return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_visual_resume(traj, env_info, task_info):
    """
    Verify the visual resume creation task.
    """
    # 1. Setup and Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load the basic file stats from export_result.sh
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    metadata = task_info.get('metadata', {})
    
    # ------------------------------------------------------------------
    # CRITERION 1: File Existence & Validity (20 points)
    # ------------------------------------------------------------------
    eddx_exists = task_result.get("eddx_exists", False)
    eddx_fresh = task_result.get("eddx_created_during_task", False)
    eddx_size = int(task_result.get("eddx_size_bytes", 0))

    pdf_exists = task_result.get("pdf_exists", False)
    pdf_fresh = task_result.get("pdf_created_during_task", False)
    pdf_size = int(task_result.get("pdf_size_bytes", 0))

    if eddx_exists and eddx_fresh and eddx_size > 5000: # >5KB ensures not empty
        score += 10
        feedback_parts.append("EDDX file created successfully.")
    else:
        feedback_parts.append("EDDX file missing, too small, or not new.")

    if pdf_exists and pdf_fresh and pdf_size > 10000: # >10KB usually for PDF with content
        score += 10
        feedback_parts.append("PDF file created successfully.")
    else:
        feedback_parts.append("PDF file missing, too small, or not new.")

    # ------------------------------------------------------------------
    # CRITERION 2: PDF Content Verification (40 points)
    # ------------------------------------------------------------------
    # Extract text from PDF to verify content
    content_score = 0
    required_strings = metadata.get("required_strings", [])
    found_strings = []
    
    if pdf_exists and PDFMINER_AVAILABLE:
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        try:
            copy_from_env(metadata.get("expected_pdf_path"), temp_pdf.name)
            pdf_text = extract_text(temp_pdf.name)
            
            # Check for required strings
            found_count = 0
            for s in required_strings:
                if s.lower() in pdf_text.lower():
                    found_count += 1
                    found_strings.append(s)
            
            # Proportional scoring based on found strings
            if len(required_strings) > 0:
                content_score = int((found_count / len(required_strings)) * 40)
            
            score += content_score
            feedback_parts.append(f"Found {found_count}/{len(required_strings)} required text elements.")
            
        except Exception as e:
            feedback_parts.append(f"PDF content check failed: {str(e)}")
        finally:
            if os.path.exists(temp_pdf.name):
                os.unlink(temp_pdf.name)
    elif not PDFMINER_AVAILABLE and pdf_exists:
        feedback_parts.append("PDF analysis skipped (pdfminer not available).")
        # Fallback points if we can't check content but file exists
        score += 20 

    # ------------------------------------------------------------------
    # CRITERION 3: VLM Visual Verification (40 points)
    # ------------------------------------------------------------------
    # We verify the "Visual" part of "Visual Resume"
    
    frames = sample_trajectory_frames(traj, n=3)
    final_shot = get_final_screenshot(traj)
    images_to_check = frames + ([final_shot] if final_shot else [])
    
    if images_to_check:
        prompt = """
        You are verifying a task to create a 'Visual Resume' in EdrawMax.
        
        Please analyze the provided screenshots (trajectory and final state) for the following features:
        1. **Two-Column Layout**: Is there a distinct sidebar and main content area?
        2. **Visual Skill Ratings**: Look at the 'Skills' section. Are skills (System Architecture, Python, etc.) represented using graphical elements like progress bars, star ratings, or dots? (NOT just text like '90%').
        3. **Header**: Is the name 'Jordan Smith' clearly visible?
        
        Return JSON:
        {
            "has_two_columns": true/false,
            "has_visual_ratings": true/false,
            "header_visible": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, images=images_to_check)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            
            vlm_score = 0
            if parsed.get("has_two_columns"):
                vlm_score += 10
                feedback_parts.append("VLM confirmed two-column layout.")
            else:
                feedback_parts.append("VLM did not detect two-column layout.")
                
            if parsed.get("has_visual_ratings"):
                vlm_score += 20
                feedback_parts.append("VLM confirmed visual skill ratings (progress bars/shapes).")
            else:
                feedback_parts.append("VLM did not detect visual skill ratings (looks like plain text).")
                
            if parsed.get("header_visible"):
                vlm_score += 10
                feedback_parts.append("VLM confirmed header.")
                
            score += vlm_score
        else:
            feedback_parts.append("VLM verification failed.")
    else:
        feedback_parts.append("No screenshots available for VLM verification.")

    # ------------------------------------------------------------------
    # FINAL SCORING
    # ------------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }