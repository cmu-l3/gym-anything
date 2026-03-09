#!/usr/bin/env python3
"""
Verifier for inspection_report_layout task.
Checks:
1. File exists and was created during task.
2. Document structure (5 sections).
3. Section orientations (P, P, L, L, P).
4. Section headers (Specific text per section).
5. Content preservation.
"""

import json
import os
import logging
import tempfile
import sys

# Import shared Writer utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inspection_report_layout(traj, env_info, task_info):
    """Verify the layout of the inspection report."""
    
    # 1. Setup and Load
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Documents/inspection_report_formatted.docx')
    
    # Get general task result (timestamps etc)
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Load DOCX
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Output file verify failed: {error}. Did you save as inspection_report_formatted.docx?"
        }

    try:
        score = 0
        feedback_parts = []
        
        # Criteria 1: File creation integrity (10 pts)
        if task_result.get('file_created_during_task', False):
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File timestamp invalid (pre-dates task)")

        # Criteria 2: Section Count (20 pts)
        # Expected: 5 sections
        # 1: Title, 2: Body, 3: App A, 4: App B, 5: App C
        num_sections = len(doc.sections)
        if num_sections == 5:
            score += 20
            feedback_parts.append("Correct section count (5)")
        else:
            feedback_parts.append(f"Incorrect section count: {num_sections} (expected 5)")

        # Criteria 3: Orientation Checks (30 pts)
        # Expected: P, P, L, L, P
        # L = Landscape (width > height), P = Portrait (height > width)
        expected_orientations = ['portrait', 'portrait', 'landscape', 'landscape', 'portrait']
        orient_score = 0
        orient_matches = []
        
        for i, section in enumerate(doc.sections):
            if i >= len(expected_orientations): break
            
            width = section.page_width
            height = section.page_height
            # If width/height are None (auto), assume standard portrait unless explicit
            is_landscape = (width is not None and height is not None and width > height)
            
            # Check explicit orientation enum if dimensions match standard
            if hasattr(section, 'orientation'):
                # WD_ORIENT.LANDSCAPE = 1
                if section.orientation == 1:
                    is_landscape = True
            
            actual = 'landscape' if is_landscape else 'portrait'
            expected = expected_orientations[i]
            
            if actual == expected:
                orient_score += 6 # 5 sections * 6 pts = 30 pts
                orient_matches.append("✓")
            else:
                orient_matches.append(f"X({actual})")
        
        score += orient_score
        feedback_parts.append(f"Orientations: {' '.join(orient_matches)}")

        # Criteria 4: Headers (30 pts)
        # 1: Empty
        # 2: "ABC Engineering" & "CONFIDENTIAL"
        # 3: "Appendix A"
        # 4: "Appendix B"
        # 5: "Appendix C"
        header_score = 0
        
        # Helper to get header text
        def get_header_text(sec):
            return " ".join([p.text for p in sec.header.paragraphs]).strip()

        # Section 1
        if num_sections > 0:
            h1 = get_header_text(doc.sections[0])
            if len(h1) < 5: # Allow very minor whitespace/artifacts
                header_score += 6
            else:
                feedback_parts.append("Sec 1 Header not empty")

        # Section 2
        if num_sections > 1:
            h2 = get_header_text(doc.sections[1])
            if "ABC Engineering" in h2 and "CONFIDENTIAL" in h2:
                header_score += 6

        # Section 3
        if num_sections > 2:
            h3 = get_header_text(doc.sections[2])
            if "Appendix A" in h3:
                header_score += 6

        # Section 4
        if num_sections > 3:
            h4 = get_header_text(doc.sections[3])
            if "Appendix B" in h4:
                header_score += 6

        # Section 5
        if num_sections > 4:
            h5 = get_header_text(doc.sections[4])
            if "Appendix C" in h5:
                header_score += 6
        
        score += header_score
        feedback_parts.append(f"Header content score: {header_score}/30")

        # Criteria 5: Content Preservation (10 pts)
        text = get_document_text(doc)
        required_phrases = ["Meridian Capital", "EPDM membrane", "cost estimates", "James R. Thornton"]
        found_phrases = sum(1 for p in required_phrases if p in text)
        if found_phrases == len(required_phrases):
            score += 10
            feedback_parts.append("Content preserved")
        else:
            feedback_parts.append("Content missing/corrupted")

        return {
            "passed": score >= 65,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Verification failed with exception")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)