#!/usr/bin/env python3
"""
Verifier for thesis_pagination_style_repair task.
Checks for removal of manual page breaks and correct application of paragraph styles.
"""

import json
import tempfile
import os
import logging
import sys

# Import gym-anything shared utils if available, or define minimal placeholders
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback for standalone testing
    query_vlm = None
    get_final_screenshot = None
    sample_trajectory_frames = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import python-docx
try:
    from docx import Document
    from docx.shared import Pt
except ImportError:
    logger.error("python-docx not installed")
    sys.exit(1)


def verify_thesis_pagination(traj, env_info, task_info):
    """
    Verify the thesis document repair.
    
    Criteria:
    1. File exists and created during task.
    2. Zero manual page breaks present (most critical).
    3. Heading 1 style has 'page_break_before' = True.
    4. Heading 2 style has 'keep_with_next' = True.
    5. Body Text style has 'widow_control' = True.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Check basic file existence via result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file 'thesis_repaired.docx' not found."
        }
        
    if not result_data.get("file_created_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file detected but timestamp indicates it wasn't modified/saved during the task."
        }

    # 2. Analyze DOCX Structure
    score = 10 # Base score for creating file
    feedback_parts = ["File created (+10)"]
    
    temp_docx = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    try:
        copy_from_env("/home/ga/Documents/thesis_repaired.docx", temp_docx.name)
        doc = Document(temp_docx.name)
        
        # --- Check A: Manual Page Breaks ---
        # Scan XML of all paragraphs for <w:br w:type="page"/>
        # python-docx doesn't always expose breaks cleanly in API, checking XML is robust.
        manual_break_count = 0
        ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
        
        for para in doc.paragraphs:
            # Check for standard manual page breaks
            breaks = para._element.findall('.//w:br[@w:type="page"]', ns)
            manual_break_count += len(breaks)
            
            # Also check rendered page breaks if explicitly inserted as hard breaks
            # (though usually w:type="page" covers Ctrl+Enter)
            
        if manual_break_count == 0:
            score += 30
            feedback_parts.append("No manual page breaks found (+30)")
        else:
            feedback_parts.append(f"FAIL: Found {manual_break_count} manual page breaks. They must be removed. (0/30)")

        # --- Check B: Heading 1 Style ---
        try:
            h1 = doc.styles['Heading 1']
            if h1.paragraph_format.page_break_before:
                score += 20
                feedback_parts.append("Heading 1 'Page Break Before' enabled (+20)")
            else:
                feedback_parts.append("FAIL: Heading 1 does not have 'Page Break Before' set (0/20)")
        except KeyError:
            feedback_parts.append("FAIL: Style 'Heading 1' missing (0/20)")

        # --- Check C: Heading 2 Style ---
        try:
            h2 = doc.styles['Heading 2']
            if h2.paragraph_format.keep_with_next:
                score += 20
                feedback_parts.append("Heading 2 'Keep With Next' enabled (+20)")
            else:
                feedback_parts.append("FAIL: Heading 2 does not have 'Keep With Next' set (0/20)")
        except KeyError:
            feedback_parts.append("FAIL: Style 'Heading 2' missing (0/20)")

        # --- Check D: Body Text Style ---
        # Note: In LibreOffice, 'Body Text' is the standard style. In python-docx, it maps to 'Body Text'.
        # However, we must ensure we are checking the style actually used in the doc.
        try:
            bt_style_name = 'Body Text'
            if bt_style_name not in doc.styles and 'BodyText' in doc.styles:
                bt_style_name = 'BodyText'
            
            bt = doc.styles[bt_style_name]
            # widow_control in python-docx maps to Widow/Orphan control
            if bt.paragraph_format.widow_control:
                score += 20
                feedback_parts.append("Body Text 'Widow/Orphan Control' enabled (+20)")
            else:
                feedback_parts.append("FAIL: Body Text widow/orphan control not enabled (0/20)")
        except KeyError:
            feedback_parts.append("FAIL: Style 'Body Text' missing (0/20)")

    except Exception as e:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Error analyzing DOCX structure: {str(e)}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_docx.name):
            os.unlink(temp_docx.name)

    # 3. Final Determination
    # Pass threshold is 85. This means they must remove manual breaks (40 total)
    # AND get at least 2 out of 3 style settings correct, OR get all styles correct and maybe miss one break (unlikely).
    # Actually, manual breaks are weighted 30. File is 10. Styles are 20+20+20 = 60.
    # Total = 100.
    # If they fail manual breaks: Max score = 70. Fail.
    # If they fix breaks but miss one style: Score = 80. Fail (strict).
    # Wait, the prompt said pass threshold 85.
    # Let's adjust scoring slightly to match "Pass Threshold: 85".
    # File(10) + Breaks(30) + H1(20) + H2(20) + Body(20) = 100.
    # If they miss one style (e.g. Body Text), score is 80.
    # This implies perfection is almost required, or 85 is too high.
    # Let's lower threshold to 80 to allow one minor style mistake, OR increase weights.
    # Decision: Keep threshold 85, strictly requiring all main components.
    
    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }