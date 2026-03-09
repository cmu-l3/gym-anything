#!/usr/bin/env python3
"""
Verifier for create_traffic_accident_sketch task.
Checks for:
1. Valid .eddx file creation with specific content (Street names, Case #, Vehicles, Skid marks).
2. Valid PDF export.
3. Timestamps indicating work was done during the task.
"""

import os
import json
import zipfile
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_traffic_accident_sketch(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load export result
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence and Timestamps (Anti-Gaming)
    eddx_exists = result_data.get("eddx_exists", False)
    eddx_fresh = result_data.get("eddx_created_during_task", False)
    eddx_size = result_data.get("eddx_size", 0)
    
    pdf_exists = result_data.get("pdf_exists", False)
    pdf_fresh = result_data.get("pdf_created_during_task", False)
    pdf_size = result_data.get("pdf_size", 0)

    if eddx_exists:
        if eddx_fresh:
            score += 10
            feedback_parts.append("EDDX file created during task (+10)")
        else:
            feedback_parts.append("EDDX file exists but has old timestamp (0)")
        
        if eddx_size > 5000: # Arbitrary small threshold for empty file
            score += 5
            feedback_parts.append("EDDX file is non-empty (+5)")
        else:
            feedback_parts.append("EDDX file is suspiciously small")
    else:
        feedback_parts.append("EDDX file missing")

    if pdf_exists:
        if pdf_fresh:
            score += 10
            feedback_parts.append("PDF export created during task (+10)")
        else:
            feedback_parts.append("PDF exists but has old timestamp (0)")
            
        if pdf_size > 5000:
            score += 5
            feedback_parts.append("PDF file is non-empty (+5)")
    else:
        feedback_parts.append("PDF export missing")

    # 2. Content Verification (Deep Check of EDDX)
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/accident_sketch_2024_891.eddx", temp_eddx.name)
            
            # EdrawMax .eddx is a ZIP archive containing XML
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Collect all text content from XML files
                    all_text = ""
                    for filename in zf.namelist():
                        if filename.endswith('.xml'):
                            try:
                                with zf.open(filename) as xml_file:
                                    all_text += xml_file.read().decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for Required Text Labels
                    required_texts = [
                        ("Oak Street", 10),
                        ("Pine Avenue", 10),
                        ("2024-891", 10)
                    ]
                    
                    for text, pts in required_texts:
                        if text.lower() in all_text.lower():
                            score += pts
                            feedback_parts.append(f"Found text '{text}' (+{pts})")
                        else:
                            feedback_parts.append(f"Missing text '{text}'")

                    # Check for Shape/Object Keywords
                    # We look for keywords that suggest use of correct libraries
                    shape_keywords = [
                        (["skid", "mark"], 10, "Skid marks"),
                        (["north", "compass"], 10, "North arrow"),
                        (["car", "sedan", "vehicle", "suv"], 20, "Vehicles")
                    ]
                    
                    for keywords, pts, desc in shape_keywords:
                        found = False
                        for kw in keywords:
                            if kw.lower() in all_text.lower():
                                found = True
                                break
                        if found:
                            score += pts
                            feedback_parts.append(f"Found {desc} (+{pts})")
                        else:
                            feedback_parts.append(f"Missing {desc} shapes")
                            
            else:
                feedback_parts.append("EDDX file is not a valid zip archive")
        except Exception as e:
            feedback_parts.append(f"Error verifying EDDX content: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # 3. Final Calculation
    passed = score >= 60  # Pass threshold
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }