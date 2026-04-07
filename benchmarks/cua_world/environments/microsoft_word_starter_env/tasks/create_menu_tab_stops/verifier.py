#!/usr/bin/env python3
"""
Verifier for create_menu_tab_stops task.

Verification Strategy:
1. File Validation: Check if 'GalaDinnerMenu.docx' exists and was modified during task.
2. XML Parsing: Extract 'word/document.xml' from the .docx (ZIP archive).
3. Formatting Check:
   - Look for <w:tab> elements with w:val="right" and w:leader="dot".
   - Check tab position is approx 6 inches (8640 twips).
4. Content Check:
   - Verify specific menu items and prices exist in the text.
   - Verify title block and section headers.
"""

import json
import os
import zipfile
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
EXPECTED_FILENAME = "GalaDinnerMenu.docx"
DOC_PATH_IN_CONTAINER = r"C:\Users\Docker\Documents\GalaDinnerMenu.docx"
RESULT_JSON_PATH = r"C:\Users\Docker\AppData\Local\Temp\task_result.json"

# Word measures: 1 inch = 1440 twips. 6 inches = 8640 twips.
TARGET_TAB_POS = 8640
TAB_TOLERANCE = 1440  # Allow +/- 1 inch (flexible layout)

def verify_create_menu_tab_stops(traj, env_info, task_info):
    """
    Verify the menu creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Temporary directory for file analysis
    with tempfile.TemporaryDirectory() as temp_dir:
        local_result_json = os.path.join(temp_dir, "task_result.json")
        local_docx = os.path.join(temp_dir, EXPECTED_FILENAME)
        
        # 1. Get Export Result JSON
        try:
            copy_from_env(RESULT_JSON_PATH, local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # Check basic file existence/creation from result
        if not result_data.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "Document 'GalaDinnerMenu.docx' was not saved."}
        
        if not result_data.get('file_created_during_task', False):
            return {"passed": False, "score": 0, "feedback": "Document was not modified during the task session (anti-gaming)."}

        # 2. Get the DOCX file
        try:
            copy_from_env(DOC_PATH_IN_CONTAINER, local_docx)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy document: {str(e)}"}

        # 3. Analyze DOCX XML
        score = 0
        feedback = []
        
        try:
            if not zipfile.is_zipfile(local_docx):
                return {"passed": False, "score": 0, "feedback": "Saved file is not a valid Word (.docx) document."}

            with zipfile.ZipFile(local_docx, 'r') as zf:
                # Read document.xml
                if 'word/document.xml' not in zf.namelist():
                    return {"passed": False, "score": 0, "feedback": "Invalid DOCX structure (missing document.xml)."}
                
                doc_xml = zf.read('word/document.xml').decode('utf-8')

                # --- CRITERION 1: Right-Aligned Tab with Dot Leader (30 pts) ---
                # Pattern: <w:tab w:val="right" w:leader="dot" w:pos="8640"/>
                # Attributes might be in any order, so regex needs care.
                
                # Broad regex for tab definitions
                tab_defs = re.findall(r'<w:tab\s+[^>]*>', doc_xml)
                
                valid_tab_found = False
                tab_feedback = "No valid tab stops found."
                
                for tab in tab_defs:
                    # Check for right alignment
                    is_right = 'w:val="right"' in tab
                    # Check for dot leader
                    has_dot = 'w:leader="dot"' in tab
                    # Check position
                    pos_match = re.search(r'w:pos="(\d+)"', tab)
                    pos_valid = False
                    if pos_match:
                        pos = int(pos_match.group(1))
                        if abs(pos - TARGET_TAB_POS) <= TAB_TOLERANCE:
                            pos_valid = True
                    
                    if is_right and has_dot:
                        if pos_valid:
                            valid_tab_found = True
                            tab_feedback = "Correct right-aligned dot-leader tab found."
                            break
                        else:
                            tab_feedback = "Right-aligned dot-leader tab found, but position is incorrect (should be approx 6 inches)."

                if valid_tab_found:
                    score += 30
                    feedback.append("Pass: Right-aligned tab with dot leader configured correctly.")
                else:
                    feedback.append(f"Fail: {tab_feedback}")

                # --- CRITERION 2: Title Formatting (15 pts) ---
                # Check for 'Annual Corporate Gala Dinner'
                # Formatting (Bold, Center) is hard to strictly bind to text in XML without complex parsing
                # simpler check: is there a run with 'Annual Corporate Gala Dinner' inside a paragraph with <w:jc w:val="center"/>?
                # We will just check existence of text and centered alignment property generally in doc
                
                full_text = re.sub(r'<[^>]+>', '', doc_xml)
                
                if "Annual Corporate Gala Dinner" in full_text:
                    score += 10
                    feedback.append("Pass: Title text present.")
                else:
                    feedback.append("Fail: Title 'Annual Corporate Gala Dinner' not found.")

                # Check for centering roughly
                if '<w:jc w:val="center"/>' in doc_xml:
                     score += 5
                     feedback.append("Pass: Centered formatting detected.")
                else:
                     feedback.append("Fail: No centered paragraphs detected.")

                # --- CRITERION 3: Menu Items and Prices (40 pts) ---
                expected_items = metadata.get('menu_items', [])
                expected_prices = metadata.get('prices', [])
                
                found_items = 0
                for item in expected_items:
                    if item in full_text:
                        found_items += 1
                
                found_prices = 0
                for price in expected_prices:
                    if price in full_text:
                        found_prices += 1
                
                # Scale score
                item_score = (found_items / len(expected_items)) * 20
                price_score = (found_prices / len(expected_prices)) * 20
                score += item_score + price_score
                
                feedback.append(f"Content Check: {found_items}/{len(expected_items)} items and {found_prices}/{len(expected_prices)} prices found.")

                # --- CRITERION 4: Dot Leader Usage Verification (15 pts) ---
                # Anti-gaming: Ensure user didn't type "........"
                # Check for runs of 4 or more periods
                manual_dots = re.search(r'\.{4,}', full_text)
                if manual_dots:
                    score -= 15 # Penalty
                    feedback.append("Penalty: Detected manual typing of dot leaders (....). Use Tab stops!")
                else:
                    if valid_tab_found: # Only award if they actually used the feature
                        score += 15
                        feedback.append("Pass: No manual dots detected.")
        
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error verifying document content: {str(e)}"}

        # Final Score Calculation
        final_score = min(100, max(0, score))
        passed = final_score >= 60 and valid_tab_found
        
        return {
            "passed": passed,
            "score": int(final_score),
            "feedback": " | ".join(feedback)
        }