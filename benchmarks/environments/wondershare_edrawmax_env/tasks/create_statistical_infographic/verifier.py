#!/usr/bin/env python3
"""
Verifier for create_statistical_infographic task.

Criteria:
1. File Existence: .eddx file and .png export must exist.
2. File Integrity: .eddx must be a valid ZIP/XML structure.
3. Content Verification (Programmatic): 
   - Title "Remote Work Impact 2024" in XML.
   - Insight text "Flexibility is the top driver" in XML.
   - Data values 45, 35, 20 in XML (representing the chart).
4. Visual Verification (VLM):
   - Confirms presence of a chart (pie/donut) and icon in the final output.
"""

import os
import json
import zipfile
import tempfile
import logging
import re
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_statistical_infographic(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    metadata = task_info.get('metadata', {})
    expected_eddx_path = metadata.get('expected_eddx_path')
    expected_png_path = metadata.get('expected_png_path')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Timestamps (20 pts) ---
    eddx_exists = task_result.get('eddx_exists', False)
    eddx_fresh = task_result.get('eddx_created_during_task', False)
    png_exists = task_result.get('png_exists', False)
    png_fresh = task_result.get('png_created_during_task', False)
    
    if eddx_exists and eddx_fresh:
        score += 10
        feedback_parts.append("EDDX file created.")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but timestamp is old.")
    else:
        feedback_parts.append("EDDX file missing.")

    if png_exists and png_fresh:
        score += 10
        feedback_parts.append("PNG export created.")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG export exists but timestamp is old.")
    else:
        feedback_parts.append("PNG export missing.")

    # --- Criterion 2 & 3: Content Verification (40 pts) ---
    # Copy EDDX file to analyze content
    content_score = 0
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(expected_eddx_path, temp_eddx.name)
            
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Extract text content from all XML files in the archive
                    all_text = ""
                    for name in zf.namelist():
                        if name.endswith('.xml') or name.endswith('.json'):
                            try:
                                all_text += zf.read(name).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Verify Title
                    if "Remote Work Impact 2024" in all_text:
                        content_score += 10
                        feedback_parts.append("Title found in file.")
                    else:
                        feedback_parts.append("Title 'Remote Work Impact 2024' NOT found.")

                    # Verify Insight Text
                    if "Flexibility" in all_text and "driver" in all_text:
                        content_score += 10
                        feedback_parts.append("Insight text found.")
                    else:
                        feedback_parts.append("Insight text NOT found.")

                    # Verify Data Values (45, 35, 20)
                    # Use simple regex to find these numbers (ignoring decimals/formatting)
                    data_points = 0
                    if re.search(r'["\'>]45["\'<]', all_text) or "0.45" in all_text:
                        data_points += 1
                    if re.search(r'["\'>]35["\'<]', all_text) or "0.35" in all_text:
                        data_points += 1
                    if re.search(r'["\'>]20["\'<]', all_text) or "0.2" in all_text:
                        data_points += 1
                    
                    if data_points == 3:
                        content_score += 20
                        feedback_parts.append("All chart data values (45, 35, 20) found.")
                    elif data_points > 0:
                        content_score += 10
                        feedback_parts.append(f"Partial data values found ({data_points}/3).")
                    else:
                        feedback_parts.append("Chart data values NOT found in file structure.")
            else:
                feedback_parts.append("EDDX is not a valid ZIP archive.")
        except Exception as e:
            feedback_parts.append(f"Error analyzing EDDX: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    score += content_score

    # --- Criterion 4: Visual Verification via VLM (40 pts) ---
    vlm_score = 0
    
    # Prefer analyzing the exported PNG if available, otherwise fallback to desktop screenshot
    image_to_analyze = None
    
    if png_exists:
        try:
            temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(expected_png_path, temp_png.name)
            image_to_analyze = temp_png.name
            feedback_parts.append("Verifying exported PNG.")
        except Exception:
            feedback_parts.append("Failed to retrieve exported PNG.")
    
    if not image_to_analyze:
        image_to_analyze = get_final_screenshot(traj)
        feedback_parts.append("Verifying final desktop screenshot.")

    if image_to_analyze:
        try:
            prompt = """
            Analyze this infographic or diagram.
            1. Is there a Pie Chart, Donut Chart, or Bar Chart visible?
            2. Is there an icon or graphic (computer, person, house, etc.) visible?
            3. Is the text "Remote Work Impact" visible?
            
            Response format JSON:
            {"chart_visible": bool, "icon_visible": bool, "title_visible": bool}
            """
            
            # Using query_vlm (assuming synchronous wrapper available or direct call)
            result = query_vlm(prompt=prompt, image=image_to_analyze)
            
            if result.get('success'):
                parsed = result.get('parsed', {})
                
                if parsed.get('chart_visible'):
                    vlm_score += 20
                    feedback_parts.append("VLM confirmed chart visibility.")
                else:
                    feedback_parts.append("VLM did not detect a chart.")
                    
                if parsed.get('icon_visible'):
                    vlm_score += 10
                    feedback_parts.append("VLM confirmed icon visibility.")
                
                if parsed.get('title_visible'):
                    vlm_score += 10
                    feedback_parts.append("VLM confirmed title visibility.")
            else:
                feedback_parts.append("VLM analysis failed.")
        except Exception as e:
            feedback_parts.append(f"VLM verification error: {e}")
        finally:
            if png_exists and image_to_analyze and os.path.exists(image_to_analyze) and image_to_analyze.endswith('.png') and 'tmp' in image_to_analyze:
                os.unlink(image_to_analyze)
    else:
        feedback_parts.append("No image available for VLM verification.")

    score += vlm_score

    # Final logic
    passed = score >= 70 and eddx_exists and eddx_fresh
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }