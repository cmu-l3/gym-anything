#!/usr/bin/env python3
"""
Verifier for create_decision_matrix task.

Verification Strategy:
1. File-based checks:
   - EDDX file exists, is valid ZIP, contains expected text strings.
   - PDF file exists (proof of export).
   - Timestamps verify creation during task.
2. VLM Verification (Trajectory & Final):
   - Verifies visual structure (table/grid).
   - Verifies color coding (green/red/yellow cells).
   - Verifies header styling and title.
"""

import os
import json
import zipfile
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_decision_matrix(traj, env_info, task_info):
    """
    Verify creation of the decision matrix.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', ["PostgreSQL", "MySQL", "MongoDB"])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. READ EXPORTED RESULT JSON
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # 2. FILE VERIFICATION (40 Points)
    # ================================================================
    
    # EDDX Check (20 pts)
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_created = result_data.get('eddx_created_during_task', False)
    eddx_size = result_data.get('eddx_size_bytes', 0)
    
    if eddx_exists and eddx_created and eddx_size > 5000:
        score += 20
        feedback_parts.append("EDDX file created successfully")
    elif eddx_exists:
        score += 10
        feedback_parts.append("EDDX file exists but timestamp/size suspicious")
    else:
        feedback_parts.append("EDDX file missing")

    # PDF Check (20 pts)
    pdf_exists = result_data.get('pdf_exists', False)
    pdf_created = result_data.get('pdf_created_during_task', False)
    pdf_size = result_data.get('pdf_size_bytes', 0)
    
    if pdf_exists and pdf_created and pdf_size > 10000:
        score += 20
        feedback_parts.append("PDF exported successfully")
    elif pdf_exists:
        score += 10
        feedback_parts.append("PDF exists but timestamp/size suspicious")
    else:
        feedback_parts.append("PDF export missing")

    # ================================================================
    # 3. CONTENT VERIFICATION (20 Points)
    # ================================================================
    # Check inside EDDX (ZIP) for key strings
    content_verified = False
    text_matches = 0
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/db_evaluation_matrix.eddx", temp_eddx.name)
            if zipfile.is_zipfile(temp_eddx.name):
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    # Search all XML files in the zip
                    all_xml_content = ""
                    for name in zf.namelist():
                        if name.endswith('.xml'):
                            try:
                                all_xml_content += zf.read(name).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    for text in required_text:
                        if text in all_xml_content:
                            text_matches += 1
                    
                    match_pct = text_matches / len(required_text)
                    if match_pct > 0.7:  # 70% match
                        score += 20
                        content_verified = True
                        feedback_parts.append(f"Content verified ({text_matches}/{len(required_text)} keywords found)")
                    elif match_pct > 0.3:
                        score += 10
                        feedback_parts.append(f"Partial content found ({text_matches}/{len(required_text)} keywords)")
                    else:
                        feedback_parts.append("Diagram content missing required keywords")
            else:
                feedback_parts.append("EDDX is not a valid zip archive")
        except Exception as e:
            feedback_parts.append(f"Content check failed: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # ================================================================
    # 4. VLM VISUAL VERIFICATION (40 Points)
    # ================================================================
    # Use trajectory frames to verify the process and final state structure
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an EdrawMax task. The user was asked to create a 'Database Technology Evaluation' matrix.
    
    Look at these screenshots. The final image should show a Table or Grid diagram.
    
    Check for:
    1. A table structure with rows and columns (NOT a flowchart, NOT a mind map).
    2. Header text visible: 'PostgreSQL', 'MySQL', 'MongoDB'.
    3. Color coding in the cells (Green, Red, Yellow fills).
    4. A title at the top: 'Database Technology Evaluation'.
    5. Dark background on the header row.
    
    JSON Response:
    {
        "is_table_structure": true/false,
        "headers_visible": true/false,
        "color_coding_visible": true/false,
        "title_visible": true/false,
        "header_styling_visible": true/false,
        "score_modifier": 0 to 100 (subjective quality score)
    }
    """
    
    vlm_result = query_vlm(
        images=frames + [final_frame], 
        prompt=vlm_prompt
    )
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('is_table_structure'): 
            vlm_score += 10
            feedback_parts.append("Visual: Table structure confirmed")
        
        if parsed.get('headers_visible'): 
            vlm_score += 10
            feedback_parts.append("Visual: Headers confirmed")
            
        if parsed.get('color_coding_visible'): 
            vlm_score += 10
            feedback_parts.append("Visual: Color coding confirmed")
            
        if parsed.get('title_visible'): 
            vlm_score += 5
            feedback_parts.append("Visual: Title confirmed")
            
        if parsed.get('header_styling_visible'): 
            vlm_score += 5
            feedback_parts.append("Visual: Header styling confirmed")
            
    score += vlm_score

    # Final Pass/Fail Logic
    # Must have created files + reasonable content + VLM visual confirmation of table
    passed = (
        eddx_created and 
        pdf_created and 
        content_verified and 
        score >= 60
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }