#!/usr/bin/env python3
"""
Verifier for design_custom_invitation_card task.

Verification Logic:
1. File Existence & Timing: Check if 'invitation.docx' exists and was modified during task.
2. Page Setup (Critical): 
   - Width = 5 inches (7200 twips)
   - Height = 7 inches (10080 twips)
   - Vertical Alignment = Center (w:vAlign w:val="center")
   - Margins = 0.5 inches (720 twips)
3. Content & Design:
   - Text content presence
   - Page Border presence
   - Shape (Star) presence
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

# Constants (1 inch = 1440 twips)
EXPECTED_WIDTH = 7200
EXPECTED_HEIGHT = 10080
EXPECTED_MARGIN = 720
TOLERANCE = 50  # Twips tolerance

def verify_design_custom_invitation_card(traj, env_info, task_info):
    """
    Verify the custom invitation card task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Define paths
    remote_json_path = "C:\\Users\\Docker\\Documents\\task_result.json"
    remote_docx_path = "C:\\Users\\Docker\\Documents\\invitation.docx"
    
    # Create temp directory
    tmp_dir = tempfile.mkdtemp(prefix="verify_invitation_")
    local_json_path = os.path.join(tmp_dir, "task_result.json")
    local_docx_path = os.path.join(tmp_dir, "invitation.docx")

    try:
        # 1. Check metadata JSON
        try:
            copy_from_env(remote_json_path, local_json_path)
            with open(local_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task result JSON: {e}"
            }

        if not result_data.get("output_exists", False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "FAIL: 'invitation.docx' not found in Documents folder."
            }

        if not result_data.get("file_created_during_task", False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "FAIL: The file exists but was not modified during the task session."
            }

        # 2. Retrieve and parse DOCX
        try:
            copy_from_env(remote_docx_path, local_docx_path)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to copy DOCX file: {e}"
            }

        if not zipfile.is_zipfile(local_docx_path):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "FAIL: Output file is not a valid DOCX file."
            }

        # Analyze Document
        score = 0
        feedback = []
        
        with zipfile.ZipFile(local_docx_path, 'r') as zf:
            try:
                document_xml = zf.read("word/document.xml").decode("utf-8")
            except KeyError:
                return {"passed": False, "score": 0, "feedback": "Invalid DOCX: missing word/document.xml"}

            # --- Criterion 1: Page Size (20 pts) ---
            # Look for <w:pgSz w:w="7200" w:h="10080" ... />
            # Regex handles attribute order variability
            pgsz_match = re.search(r'<w:pgSz\s+[^>]*>', document_xml)
            width_ok = False
            height_ok = False
            
            if pgsz_match:
                tag = pgsz_match.group(0)
                w_match = re.search(r'w:w="(\d+)"', tag)
                h_match = re.search(r'w:h="(\d+)"', tag)
                
                if w_match:
                    w = int(w_match.group(1))
                    if abs(w - EXPECTED_WIDTH) < TOLERANCE:
                        width_ok = True
                
                if h_match:
                    h = int(h_match.group(1))
                    if abs(h - EXPECTED_HEIGHT) < TOLERANCE:
                        height_ok = True

            if width_ok and height_ok:
                score += 20
                feedback.append("PASS: Page size 5x7 inches configured correctly.")
            else:
                feedback.append(f"FAIL: Page size incorrect. Expected 5x7 inches (7200x10080 twips).")

            # --- Criterion 2: Margins (10 pts) ---
            # Look for <w:pgMar ... w:top="720" ... />
            pgmar_match = re.search(r'<w:pgMar\s+[^>]*>', document_xml)
            margins_ok = False
            if pgmar_match:
                tag = pgmar_match.group(0)
                # Check top, bottom, left, right
                sides = ['top', 'bottom', 'left', 'right']
                sides_correct = 0
                for side in sides:
                    m = re.search(rf'w:{side}="(\d+)"', tag)
                    if m and abs(int(m.group(1)) - EXPECTED_MARGIN) < TOLERANCE:
                        sides_correct += 1
                
                if sides_correct >= 4:
                    margins_ok = True
            
            if margins_ok:
                score += 10
                feedback.append("PASS: Margins set to 0.5 inches.")
            else:
                feedback.append("FAIL: Margins not set to 0.5 inches (720 twips).")

            # --- Criterion 3: Vertical Alignment (25 pts) ---
            # Look for <w:vAlign w:val="center"/>
            valign_match = re.search(r'<w:vAlign\s+w:val="center"', document_xml)
            if valign_match:
                score += 25
                feedback.append("PASS: Vertical Alignment set to Center.")
            else:
                feedback.append("FAIL: Vertical Alignment not set to Center (did you use Page Setup > Layout?).")

            # --- Criterion 4: Page Border (10 pts) ---
            # Look for <w:pgBorders>
            if "<w:pgBorders" in document_xml:
                score += 10
                feedback.append("PASS: Page border detected.")
            else:
                feedback.append("FAIL: No page border found.")

            # --- Criterion 5: Shape/Star (10 pts) ---
            # Look for drawing element. Shapes usually appear as <w:drawing> containing visual properties.
            # Stars often have prst="star5" in preset geometry
            if "<w:drawing>" in document_xml or "<v:shape" in document_xml:
                # Check for star specifically if possible, but basic shape presence is good proxy for now
                # In strict XML, a star is <a:prstGeom prst="star5"> inside the drawing
                if 'prst="star5"' in document_xml or 'type="#_x0000_t12"' in document_xml: # t12 is legacy star
                    score += 10
                    feedback.append("PASS: Star shape detected.")
                else:
                    score += 5 # Points for a shape, but maybe not a star
                    feedback.append("PARTIAL: Shape detected, but verify it is a star.")
            else:
                feedback.append("FAIL: No shapes detected (Star missing).")

            # --- Criterion 6: Text Content (15 pts) ---
            # Check for key phrases
            required_phrases = ["SAVE THE DATE", "Summit Innovations", "Gala", "October"]
            text_content = re.sub(r'<[^>]+>', '', document_xml) # Naive strip tags
            phrases_found = 0
            for phrase in required_phrases:
                if phrase in text_content or phrase in document_xml: # XML might split text, but simple check helps
                    phrases_found += 1
            
            if phrases_found >= 3:
                score += 15
                feedback.append(f"PASS: Text content found ({phrases_found}/{len(required_phrases)} phrases).")
            else:
                feedback.append(f"FAIL: Missing required text content. Found {phrases_found} phrases.")

            # --- Criterion 7: Formatting (Center/Bold) (10 pts) ---
            # Check for <w:jc w:val="center"/> (Justification Center)
            # Check for <w:b/> (Bold)
            if '<w:jc w:val="center"/>' in document_xml:
                score += 5
            if '<w:b/>' in document_xml or '<w:b w:val="1"/>' in document_xml:
                score += 5
            
            if score >= 90:
                feedback.append("PASS: Document saved and file exists (Implicit 10pts).")
                score += 10
            elif score >= 10:
                # If they did some work, give points for saving
                score += 10
                feedback.append("PASS: File saved.")

        # Final check
        passed = score >= 60 and width_ok and height_ok and valign_match
        
        return {
            "passed": bool(passed),
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)