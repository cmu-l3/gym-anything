#!/usr/bin/env python3
"""
Verifier for esa_report_sections task.

Criteria:
1. Document structure: At least 3 sections (Cover, Body, Data/Appendices).
2. Orientation: At least one section must be Landscape.
3. Headers:
   - First section (Cover) must NOT have the project header.
   - Body sections must have "ESA-2024-0472" in header.
4. Styles: Key headings ("Executive Summary", "Site Maps...", etc.) must be Heading 1.
5. Page Numbers: Footer must contain page numbering (except cover).
"""

import json
import os
import logging
import sys
import shutil
import tempfile

# Add utils path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    vlm_verify_screenshot
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_esa_report(traj, env_info, task_info):
    """Verify ESA report formatting and structuring."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Documents/esa_formatted.docx')
    project_id = metadata.get('project_id', "ESA-2024-0472")
    
    # 1. Load result JSON from export script
    result_json_path = "/tmp/task_result.json"
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file esa_formatted.docx not found"}
        
    if not task_result.get("file_modified_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task (creation time mismatch)"}

    # 2. Parse the DOCX file
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse output document: {error}"}

    score = 0
    feedback_parts = []
    
    try:
        # --- CRITERION 1: Section Count (15 pts) ---
        # We expect at least 3 sections: Cover, Body, Landscape Data
        section_count = len(doc.sections)
        if section_count >= 3:
            score += 15
            feedback_parts.append(f"Section breaks added ({section_count} sections)")
        elif section_count == 2:
            score += 5
            feedback_parts.append("Only 2 sections found (expected >= 3)")
        else:
            feedback_parts.append("Document still has only 1 section")

        # --- CRITERION 2: Landscape Orientation (15 pts) ---
        # Check if any section has width > height
        has_landscape = False
        for i, section in enumerate(doc.sections):
            width = section.page_width
            height = section.page_height
            # python-docx uses Emu, but comparison works
            if width and height and width > height:
                has_landscape = True
                break
        
        if has_landscape:
            score += 15
            feedback_parts.append("Landscape section found")
        else:
            feedback_parts.append("No landscape section found")

        # --- CRITERION 3: Headers (22 pts) ---
        # Cover page (Section 0) should NOT have the specific header
        # Subsequent sections SHOULD have the header
        
        # Check Section 0 (Cover)
        sec0_header_text = ""
        if len(doc.sections) > 0:
            header = doc.sections[0].header
            if header:
                sec0_header_text = " ".join([p.text for p in header.paragraphs]).strip()
        
        # Check subsequent sections
        body_header_found = False
        for i in range(1, len(doc.sections)):
            header = doc.sections[i].header
            if header:
                text = " ".join([p.text for p in header.paragraphs]).strip()
                if project_id in text:
                    body_header_found = True
                    break
        
        # Logic: 
        # - If 1 section total: Fail headers (can't differ)
        # - If >1 sections:
        #   - Sec 0 shouldn't have ID (or should be empty)
        #   - Later sec should have ID
        
        if section_count > 1:
            if project_id not in sec0_header_text:
                score += 10
                feedback_parts.append("Cover page header correct (empty/different)")
            else:
                feedback_parts.append("Cover page header contains Project ID (should be clean)")
                
            if body_header_found:
                score += 12
                feedback_parts.append("Body header contains Project ID")
            else:
                feedback_parts.append("Body header missing Project ID")
        else:
            feedback_parts.append("Cannot verify header distinction (single section)")

        # --- CRITERION 4: Heading Styles (25 pts) ---
        expected_h1 = metadata.get("heading_1_titles", [])
        expected_h2 = metadata.get("heading_2_titles", [])
        
        h1_found = 0
        h2_found = 0
        
        # Get all paragraph styles mapped to text
        # Simple fuzzy match: if paragraph contains the title, check style
        for para in doc.paragraphs:
            text = para.text.strip()
            style = para.style.name if para.style else ""
            
            # Check H1
            for title in expected_h1:
                if title in text and "Heading 1" in style:
                    h1_found += 1
                    # Avoid double counting same title if repeated (unlikely here)
                    break
            
            # Check H2
            for title in expected_h2:
                if title in text and "Heading 2" in style:
                    h2_found += 1
                    break
        
        # Cap counts at length of expected lists (in case of duplicates)
        h1_found = min(h1_found, len(expected_h1))
        h2_found = min(h2_found, len(expected_h2))
        
        # Scoring: Proportional
        if len(expected_h1) > 0:
            score += int(15 * (h1_found / len(expected_h1)))
        if len(expected_h2) > 0:
            score += int(10 * (h2_found / len(expected_h2)))
            
        feedback_parts.append(f"Heading 1 styles: {h1_found}/{len(expected_h1)}")
        feedback_parts.append(f"Heading 2 styles: {h2_found}/{len(expected_h2)}")

        # --- CRITERION 5: Page Numbers (8 pts) ---
        # Check XML for page number field
        has_page_num = False
        # Only check if we have sections
        if len(doc.sections) > 0:
            # Check footers of all sections
            for section in doc.sections:
                footer = section.footer
                if not footer: continue
                # Check all paragraphs in footer for w:fldChar or "PAGE"
                for p in footer.paragraphs:
                    if "PAGE" in p._element.xml or "w:fldChar" in p._element.xml:
                        has_page_num = True
                        break
                if has_page_num: break
        
        if has_page_num:
            score += 8
            feedback_parts.append("Page numbers detected")
        else:
            feedback_parts.append("Page numbers missing in footer")

        # --- CRITERION 6: VLM Verification (15 pts) ---
        # Visual check for structure/layout
        vlm_result = vlm_verify_screenshot(env_info, traj, 
            "Analyze this LibreOffice Writer screenshot. "
            "1. Do you see a document with headers? "
            "2. Is there a landscape page visible (wider than tall)? "
            "3. Do headings look styled (larger/bold)? "
            "Return JSON: {'has_headers': bool, 'is_landscape': bool, 'styled_headings': bool}"
        )
        
        if vlm_result['success']:
            parsed = vlm_result['parsed']
            if parsed.get('is_landscape', False) or parsed.get('has_headers', False):
                score += 15
                feedback_parts.append("Visual layout verified")
        else:
            # Fallback if VLM fails but program check passed landscape
            if has_landscape: 
                score += 15
                feedback_parts.append("Visual check skipped (programmatic pass)")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        feedback_parts.append(f"Error during check: {str(e)}")
    finally:
        cleanup_verification_temp(temp_dir)

    # Final tally
    passed = (score >= 60) and (section_count >= 3) and has_landscape
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }