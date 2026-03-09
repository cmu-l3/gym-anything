#!/usr/bin/env python3
"""
Verifier for design_award_certificate task.

Criteria:
1. Files (.eddx, .pdf, .png) exist and were created during task.
2. .eddx file content contains specific text strings (Recipient, Company, etc.).
3. VLM verification of the visual result (Border, Seal, Landscape layout).
"""

import json
import os
import tempfile
import zipfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_award_certificate(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', ["Jordan Lee", "Summit Tech Solutions", "Certificate of Achievement"])
    
    # Weights
    SCORE_FILES = 30  # 10 pts each file type
    SCORE_TIMESTAMPS = 10 # Anti-gaming
    SCORE_CONTENT = 30 # Text strings in EDDX
    SCORE_VLM = 30 # Visual check
    
    score = 0
    feedback_parts = []
    
    # 1. Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    files_info = result.get("files", {})
    
    # 2. Check Files Existence (30 pts)
    eddx_ok = files_info.get("eddx", {}).get("exists", False)
    pdf_ok = files_info.get("pdf", {}).get("exists", False)
    png_ok = files_info.get("png", {}).get("exists", False)
    
    if eddx_ok: score += 10
    if pdf_ok: score += 10
    if png_ok: score += 10
    
    if not eddx_ok and not pdf_ok and not png_ok:
        return {"passed": False, "score": 0, "feedback": "No output files found."}

    feedback_parts.append(f"Files found: EDDX={eddx_ok}, PDF={pdf_ok}, PNG={png_ok}")

    # 3. Check Timestamps (Anti-gaming) (10 pts)
    # Only award if at least one file exists and ALL existing files were created during task
    valid_timestamps = True
    for ftype in ["eddx", "pdf", "png"]:
        if files_info.get(ftype, {}).get("exists", False):
            if not files_info.get(ftype, {}).get("created_during_task", False):
                valid_timestamps = False
    
    if valid_timestamps and (eddx_ok or pdf_ok or png_ok):
        score += 10
    elif not valid_timestamps:
        feedback_parts.append("WARNING: Some files existed before task start (anti-gaming penalty).")

    # 4. Check EDDX Content (30 pts)
    # Download .eddx and unzip to find text
    content_score = 0
    if eddx_ok:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/certificate_jordan_lee.eddx", temp_eddx.name)
            
            # EdrawMax files are ZIPs containing XML
            found_text = {text: False for text in required_text}
            
            try:
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Combine all XML content to search
                    all_xml_content = ""
                    for name in zf.namelist():
                        if name.endswith('.xml'):
                            try:
                                all_xml_content += zf.read(name).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Search for required strings
                    for text in required_text:
                        if text in all_xml_content:
                            found_text[text] = True
            except zipfile.BadZipFile:
                feedback_parts.append("EDDX file is not a valid ZIP archive.")
            
            # Calculate content score
            found_count = sum(found_text.values())
            total_req = len(required_text)
            if total_req > 0:
                content_score = int((found_count / total_req) * SCORE_CONTENT)
            
            score += content_score
            feedback_parts.append(f"Text check: {found_count}/{total_req} strings found in project file.")
            
        except Exception as e:
            feedback_parts.append(f"Error analyzing EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    else:
        feedback_parts.append("Skipping content check (EDDX missing).")

    # 5. VLM Verification (30 pts)
    # Use standard VLM utility from framework
    vlm_score = 0
    try:
        from gym_anything.vlm import query_vlm, get_final_screenshot
        
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            prompt = """
            You are verifying a graphic design task. The user was asked to design an 'Employee of the Month' certificate for 'Jordan Lee'.
            
            Please analyze the image and answer the following in JSON format:
            {
                "is_certificate": true/false,
                "has_border": true/false,
                "has_seal_or_badge": true/false,
                "recipient_name_visible": true/false,
                "is_landscape": true/false,
                "overall_quality": "poor/acceptable/good"
            }
            
            - is_certificate: Does it look like an award certificate?
            - has_border: Is there a decorative border around the edges?
            - has_seal_or_badge: Is there a ribbon, medal, or seal icon?
            - recipient_name_visible: Can you clearly read 'Jordan Lee'?
            - is_landscape: Is the page wider than it is tall?
            """
            
            vlm_result = query_vlm(images=[final_screenshot], prompt=prompt)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                criteria_met = 0
                if parsed.get("is_certificate"): criteria_met += 1
                if parsed.get("has_border"): criteria_met += 1
                if parsed.get("has_seal_or_badge"): criteria_met += 1
                if parsed.get("recipient_name_visible"): criteria_met += 1
                if parsed.get("is_landscape"): criteria_met += 1
                
                # 5 criteria * 6 points = 30 max
                vlm_score = criteria_met * 6
                score += vlm_score
                feedback_parts.append(f"Visual verification: {criteria_met}/5 criteria met.")
            else:
                feedback_parts.append("VLM analysis failed.")
        else:
            feedback_parts.append("No screenshot available for visual verification.")
            
    except ImportError:
        feedback_parts.append("VLM module not available (skipping visual verification).")
        # Fallback: if EDDX text check passed perfectly, assume reasonable visual attempt
        if content_score >= 20:
             score += 15
             feedback_parts.append("awarding partial visual points based on content correctness")

    # Final Check
    passed = (score >= 70) and eddx_ok and pdf_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }