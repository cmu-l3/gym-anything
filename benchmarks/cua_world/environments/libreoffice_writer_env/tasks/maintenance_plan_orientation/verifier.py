#!/usr/bin/env python3
"""
Verifier for maintenance_plan_orientation task.
Checks for section breaks, landscape orientation, heading styles, and page numbers.
"""

import json
import os
import sys
import logging
import tempfile
import shutil

# Import shared utils if available
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_heading_styles
)
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_maintenance_plan(traj, env_info, task_info):
    """
    Verify the maintenance plan reformatting.
    
    Criteria:
    1. Output file exists and is modified (10 pts)
    2. Document has at least 3 sections (15 pts)
    3. At least one section is Landscape (20 pts)
    4. First and Last sections are Portrait (20 pts)
    5. Heading 1 styles applied correctly (15 pts)
    6. Page numbers detected in footer (10 pts)
    7. VLM visual confirmation of layout (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_headings = metadata.get('required_headings', [])
    output_path = metadata.get('output_path', '/home/ga/Documents/maintenance_plan_formatted.docx')

    score = 0
    feedback_parts = []
    
    # 1. Check file existence from task_result.json
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result_data = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    score += 10
    feedback_parts.append("File created")

    # 2. Parse DOCX for structural checks
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')
    if not success:
        return {"passed": False, "score": score, "feedback": f"File exists but corrupted: {error}"}

    try:
        # Check Section Count
        num_sections = len(doc.sections)
        if num_sections >= 3:
            score += 15
            feedback_parts.append(f"Sections created ({num_sections} found)")
        else:
            feedback_parts.append(f"Insufficient sections ({num_sections} found, expected >= 3)")

        # Check Orientation
        # WD_ORIENT.PORTRAIT=0, LANDSCAPE=1. But simpler to check dimensions.
        has_landscape = False
        first_portrait = False
        last_portrait = False
        
        for i, section in enumerate(doc.sections):
            width = section.page_width
            height = section.page_height
            
            # None checks handles auto/default
            is_landscape = (width is not None and height is not None and width > height) or \
                           (section.orientation == 1)
            
            if is_landscape:
                has_landscape = True
                
            if i == 0 and not is_landscape:
                first_portrait = True
            if i == len(doc.sections) - 1 and not is_landscape:
                last_portrait = True
        
        if has_landscape:
            score += 20
            feedback_parts.append("Landscape section found")
        else:
            feedback_parts.append("No landscape section detected")
            
        if first_portrait and last_portrait:
            score += 20
            feedback_parts.append("Portrait orientation preserved for narrative")
        elif first_portrait or last_portrait:
            score += 10
            feedback_parts.append("Partial portrait orientation correct")
        else:
            feedback_parts.append("Narrative sections not in portrait")

        # Check Heading Styles
        heading_map = {h: 'Heading 1' for h in required_headings}
        h_matched, h_total, h_feed = check_heading_styles(doc, heading_map)
        if h_matched >= 3:
            score += 15
            feedback_parts.append(f"Headings formatted ({h_matched}/{h_total})")
        else:
            feedback_parts.append(f"Headings missing style ({h_matched}/{h_total})")

        # Check Page Numbers (Footer analysis)
        has_page_numbers = False
        # Look in all sections' footers
        for section in doc.sections:
            footer = section.footer
            if not footer: 
                continue
            xml = footer._element.xml
            # Look for PAGE field or simple field
            if 'w:fldSimple' in xml and 'PAGE' in xml:
                has_page_numbers = True
                break
            if 'w:instrText' in xml and 'PAGE' in xml:
                has_page_numbers = True
                break
        
        if has_page_numbers:
            score += 10
            feedback_parts.append("Page numbers detected")
        else:
            feedback_parts.append("No page numbers found in footer")

    except Exception as e:
        feedback_parts.append(f"Verification error: {str(e)}")
    finally:
        cleanup_verification_temp(temp_dir)

    # 3. VLM Verification
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot and query_vlm:
        prompt = """
        Analyze this screenshot of LibreOffice Writer.
        1. Can you see a document with pages?
        2. Are any pages in Landscape orientation (wider than tall)?
        3. Is there a page number visible in the footer area?
        4. Is there a table visible?
        
        Respond with JSON:
        {"landscape_visible": bool, "page_numbers_visible": bool, "table_visible": bool}
        """
        try:
            res = query_vlm(prompt, image=final_screenshot)
            if res.get('success'):
                parsed = res.get('parsed', {})
                if parsed.get('landscape_visible') or parsed.get('table_visible'):
                    vlm_score += 10
                    feedback_parts.append("Visual confirmation of layout")
        except Exception:
            pass
            
    score += vlm_score

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }