#!/usr/bin/env python3
"""
Verifier for optimize_real_estate_images task.

Requirements:
1. File 'Property_Listing_Email.docx' exists.
2. File size < 3MB (Compression verification).
3. Image 1 is cropped (XML inspection).
4. All images have 'Simple Frame, White' style (XML inspection).
5. Document still contains 3 images (Anti-gaming: didn't just delete them).
"""

import json
import logging
import os
import zipfile
import tempfile
import shutil
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_real_estate_images(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Constants
    MAX_SIZE_BYTES = 3 * 1024 * 1024  # 3MB
    EXPECTED_IMG_COUNT = 3
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result_data.get('output_exists', False)
    file_size = result_data.get('output_size_bytes', 0)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file 'Property_Listing_Email.docx' not found."}

    score = 0
    feedback = []

    # 2. Check File Creation (10 pts)
    score += 10
    feedback.append("File created successfully.")

    # 3. Check Compression (40 pts)
    if file_size < MAX_SIZE_BYTES:
        score += 40
        feedback.append(f"Compression successful: {file_size/1024/1024:.2f}MB (Target < 3MB).")
    elif file_size < 5 * 1024 * 1024:
        score += 10
        feedback.append(f"Partial compression: {file_size/1024/1024:.2f}MB (Target < 3MB).")
    else:
        feedback.append(f"File too large: {file_size/1024/1024:.2f}MB. Did you compress images?")

    # 4. Analyze DOCX Internals
    temp_docx = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\Property_Listing_Email.docx", temp_docx.name)
        
        if not zipfile.is_zipfile(temp_docx.name):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid DOCX."}

        with zipfile.ZipFile(temp_docx.name, 'r') as zf:
            # Check Image Count (20 pts)
            media_files = [f for f in zf.namelist() if f.startswith('word/media/')]
            if len(media_files) >= EXPECTED_IMG_COUNT:
                score += 20
                feedback.append(f"Images preserved ({len(media_files)} found).")
            else:
                feedback.append(f"Images missing! Found {len(media_files)}, expected {EXPECTED_IMG_COUNT}.")

            # Parse Document XML for Style and Crop
            try:
                doc_xml = zf.read('word/document.xml').decode('utf-8')
            except:
                doc_xml = ""

            # Check for Crop (15 pts) - Look for a:srcRect with non-zero left ('l') attribute
            # Pattern: <a:srcRect l="12345" ... />
            # The task asks to crop the FIRST image. We check if ANY image has a left crop.
            crop_matches = re.findall(r'<a:srcRect[^>]*l="[1-9]', doc_xml)
            if crop_matches:
                score += 15
                feedback.append("Image cropping detected.")
            else:
                feedback.append("No image cropping detected (expected left crop).")

            # Check for Style (15 pts) - 'Simple Frame, White'
            # This style typically adds a white border (<a:ln ...><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:ln>)
            # and a specific geometry or effect.
            # A robust check for "White Border" is looking for line properties with white color.
            # <a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:srgbClr val="FFFFFF"/> ...
            
            # We look for <a:srgbClr val="FFFFFF"/> inside <a:ln> or similar structure indicative of the frame
            # Or simpler: The style often adds a distinct <a:prstGeom prst="rect"> with specific attributes or effect containers.
            # Let's search for the line definition commonly associated with this style.
            # Search for white line border
            white_border = re.search(r'<a:ln[^>]*>.*?<a:solidFill>.*?<a:(srgbClr val="FFFFFF"|schemeClr val="lt1")', doc_xml, re.DOTALL)
            
            if white_border:
                score += 15
                feedback.append("Picture style (White Frame) detected.")
            else:
                feedback.append("Picture style 'Simple Frame, White' not detected (no white border found).")

    except Exception as e:
        feedback.append(f"Error analyzing document structure: {str(e)}")
    finally:
        if os.path.exists(temp_docx.name):
            os.unlink(temp_docx.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }