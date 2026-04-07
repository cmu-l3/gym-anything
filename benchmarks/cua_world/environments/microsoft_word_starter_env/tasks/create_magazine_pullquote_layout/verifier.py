#!/usr/bin/env python3
"""
Verifier for create_magazine_pullquote_layout task.

Verification Criteria:
1. File Verification (Core):
   - 'Alumni_Feature_Formatted.docx' exists and was modified/created during the task.
   - File is a valid ZIP/DOCX archive.

2. Structure Verification (XML Parsing):
   - Two Columns: The document must have a section with <w:cols w:num="2">.
     Ideally, the title should be in a separate section (w:num="1") or the 2-column section starts after it.
   - Text Box Exists: A <w:drawing>, <w:pict>, or <v:shape> containing the quote.
   - Quote Content: The text box must contain the specific quote string.
   - Text Wrapping: The text box must have wrapping set to 'Square' or 'Tight' (e.g., <wp:wrapSquare>).

3. Formatting (Bonus/Robustness):
   - Text box has a border (outline).
   - Text box has white fill (to obscure text behind it, though hard to verify purely via XML without complex logic).
   - Alignment: Center alignment properties.

Scoring:
- File exists & valid: 20 pts
- Two-column layout applied: 30 pts
- Text box with correct quote found: 25 pts
- Text wrapping correct (Square/Tight): 25 pts
- Total: 100 pts
"""

import json
import logging
import os
import re
import shutil
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
RESULT_JSON_PATH = "C:\\Users\\Docker\\task_result.json"
EXPECTED_DOC_PATH = "C:\\Users\\Docker\\Documents\\Alumni_Feature_Formatted.docx"
REQUIRED_QUOTE_SNIPPET = "realization of tomorrow"

def verify_create_magazine_pullquote_layout(traj, env_info, task_info):
    """Verify the magazine layout task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_dir = tempfile.mkdtemp(prefix="verify_mag_layout_")
    try:
        # 1. Fetch Result JSON
        local_json_path = os.path.join(temp_dir, "result.json")
        try:
            copy_from_env(RESULT_JSON_PATH, local_json_path)
            with open(local_json_path, "r") as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        if not result_data.get("output_exists", False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file 'Alumni_Feature_Formatted.docx' not found in Documents folder."
            }

        # 2. Fetch Document
        local_docx_path = os.path.join(temp_dir, "Alumni_Feature_Formatted.docx")
        try:
            copy_from_env(EXPECTED_DOC_PATH, local_docx_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy output document: {e}"}

        if not zipfile.is_zipfile(local_docx_path):
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid .docx file."}

        # 3. Analyze Document XML
        score = 20  # Base score for file existing
        feedback = ["File saved successfully."]
        
        with zipfile.ZipFile(local_docx_path, "r") as zf:
            try:
                doc_xml = zf.read("word/document.xml").decode("utf-8", errors="replace")
            except KeyError:
                return {"passed": False, "score": score, "feedback": "Invalid DOCX: missing word/document.xml"}

            # Check 3.1: Two Columns
            # Look for <w:cols ... w:num="2" ...>
            # Word 2010 usually puts this in <w:sectPr>
            cols_match = re.search(r'<w:cols[^>]*w:num="2"[^>]*>', doc_xml)
            if cols_match:
                score += 30
                feedback.append("Two-column layout detected.")
            else:
                feedback.append("FAIL: Two-column layout not detected (w:num='2' missing).")

            # Check 3.2: Pull Quote Content
            # The text might be in document.xml (if simple text box) or usually is, 
            # but sometimes in word/headerX.xml if anchored there (unlikely for this task).
            # Text boxes in Word 2010 often appear inside <w:drawing> -> <wp:docPr> ... and the text is inside <w:txbxContent>
            
            # Normalize xml to search for text
            quote_found = REQUIRED_QUOTE_SNIPPET.lower() in doc_xml.lower()
            
            if quote_found:
                score += 25
                feedback.append("Pull-quote text found in document.")
            else:
                feedback.append(f"FAIL: Quote text '{REQUIRED_QUOTE_SNIPPET}...' not found.")

            # Check 3.3: Text Wrapping
            # Look for wrapping tags associated with drawings.
            # <wp:wrapSquare> or <wp:wrapTight>
            # Note: This is a heuristic. If there are multiple images, this might give a false positive, 
            # but the starting doc has none.
            wrap_square = "<wp:wrapSquare" in doc_xml
            wrap_tight = "<wp:wrapTight" in doc_xml
            
            if wrap_square or wrap_tight:
                score += 25
                feedback.append("Text wrapping (Square/Tight) applied.")
            else:
                # Fallback: check for VML wrapping if saved in compatibility mode (unlikely for new doc but possible)
                vml_wrap = "type=\"square\"" in doc_xml or "type=\"tight\"" in doc_xml
                if vml_wrap:
                    score += 25
                    feedback.append("Text wrapping detected (VML format).")
                else:
                    feedback.append("FAIL: Text wrapping not set to Square or Tight (text may be blocked).")

        # Final Evaluation
        passed = score >= 85
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)