#!/usr/bin/env python3
"""
Verifier for format_screenplay_scene task.

Verification Logic:
1. Check if 'Formatted_Script.docx' exists and was modified during task.
2. Parse the DOCX XML (word/document.xml) to verify:
   - Font is Courier New, 12pt (24 half-pts) globally.
   - Page Margins are correct (Left 1.5", others 1.0").
   - Character names (e.g., "ROOK") have ~2.0" left indent.
   - Dialogue has ~1.0" left indent and ~1.5" right indent.
   - Parentheticals have ~1.5" left indent.
"""

import json
import logging
import os
import zipfile
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants (Twips: 1 inch = 1440 twips)
TOLERANCE = 100  # +/- ~0.07 inches
EXPECTED_MARGINS = {
    "top": 1440,
    "bottom": 1440,
    "left": 2160,  # 1.5"
    "right": 1440
}
EXPECTED_INDENTS = {
    "character": 2880,      # 2.0"
    "dialogue_left": 1440,  # 1.0"
    "dialogue_right": 2160, # 1.5"
    "parenthetical": 2160   # 1.5"
}

def verify_format_screenplay_scene(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Define paths
    result_json_remote = "C:\\Users\\Docker\\format_screenplay_scene_result.json"
    docx_remote = "C:\\Users\\Docker\\Documents\\Formatted_Script.docx"
    
    # Create temp dir for verification artifacts
    with tempfile.TemporaryDirectory() as tmp_dir:
        result_json_local = os.path.join(tmp_dir, "result.json")
        docx_local = os.path.join(tmp_dir, "Formatted_Script.docx")
        
        # 1. Get Result JSON
        try:
            copy_from_env(result_json_remote, result_json_local)
            with open(result_json_local, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task result JSON: {str(e)}"
            }

        # Basic Checks
        if not result_data.get("output_exists"):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file 'Formatted_Script.docx' not found."
            }
        
        if not result_data.get("file_created_during_task"):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file was not modified during the task session."
            }

        # 2. Get DOCX File
        try:
            copy_from_env(docx_remote, docx_local)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve output file: {str(e)}"
            }

        if not zipfile.is_zipfile(docx_local):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file is not a valid DOCX file."
            }

        # 3. Analyze XML
        score = 0
        feedback = []
        
        try:
            with zipfile.ZipFile(docx_local, 'r') as zf:
                doc_xml = zf.read('word/document.xml').decode('utf-8')
                
                # --- Criterion 1: Font (Courier New 12pt) (20 pts) ---
                # Check for rFonts w:ascii="Courier New"
                font_match = re.search(r'<w:rFonts[^>]*w:ascii="Courier New"', doc_xml, re.IGNORECASE)
                # Check for size w:val="24" (12pt)
                size_match = re.search(r'<w:sz[^>]*w:val="24"', doc_xml)
                
                if font_match and size_match:
                    score += 20
                    feedback.append("Font correct (Courier New 12pt)")
                elif font_match:
                    score += 10
                    feedback.append("Font face correct, but size incorrect")
                else:
                    feedback.append("Font incorrect (expected Courier New)")

                # --- Criterion 2: Page Margins (20 pts) ---
                # Look for <w:pgMar ... w:left="2160" ... >
                # Note: attributes can be in any order
                pg_mar_match = re.search(r'<w:pgMar[^>]*>', doc_xml)
                if pg_mar_match:
                    tag = pg_mar_match.group(0)
                    
                    # Helper to extract attr value
                    def get_attr(name, text):
                        m = re.search(f'{name}="(\d+)"', text)
                        return int(m.group(1)) if m else None

                    left = get_attr("w:left", tag)
                    right = get_attr("w:right", tag)
                    top = get_attr("w:top", tag)
                    bottom = get_attr("w:bottom", tag)
                    
                    margins_ok = True
                    if not (left and abs(left - EXPECTED_MARGINS["left"]) < TOLERANCE): margins_ok = False
                    if not (right and abs(right - EXPECTED_MARGINS["right"]) < TOLERANCE): margins_ok = False
                    
                    if margins_ok:
                        score += 20
                        feedback.append("Page margins correct")
                    else:
                        feedback.append(f"Page margins incorrect (Found Left: {left}, Right: {right})")
                else:
                    feedback.append("Page margins not found in XML")

                # --- Criterion 3: Indentation (40 pts total) ---
                # We need to find specific paragraphs and check their indentation.
                # Since XML is continuous, we look for text, then look backwards for the nearest <w:pPr>
                
                # Helper: Find indentation for a specific text string
                def check_indent(target_text, expected_left, expected_right=None):
                    # Find text index
                    text_idx = doc_xml.find(target_text)
                    if text_idx == -1:
                        return False, f"Text '{target_text}' not found"
                    
                    # Find last <w:pPr> before this text
                    # We search backwards from text_idx
                    preceding_xml = doc_xml[:text_idx]
                    p_start = preceding_xml.rfind('<w:p>')
                    if p_start == -1: p_start = 0
                    
                    p_block = doc_xml[p_start:text_idx+200] # Grab chunk around text
                    
                    ind_match = re.search(r'<w:ind[^>]*>', p_block)
                    if not ind_match:
                        # No indent tag usually means 0 indent, unless defined in style. 
                        # But task requires explicit settings.
                        # However, 0 indent is not what we expect for these elements.
                        return False, "No indentation tag found"
                    
                    tag = ind_match.group(0)
                    
                    def get_val(name, text):
                        m = re.search(f'{name}="(\d+)"', text)
                        return int(m.group(1)) if m else 0

                    actual_left = get_val("w:left", tag)
                    actual_right = get_val("w:right", tag)
                    
                    left_ok = abs(actual_left - expected_left) < TOLERANCE
                    right_ok = True
                    if expected_right is not None:
                        right_ok = abs(actual_right - expected_right) < TOLERANCE
                        
                    return (left_ok and right_ok), f"Found L:{actual_left} R:{actual_right}"

                # 3a. Character Indent (ROOK) - 2.0" (2880)
                char_ok, char_msg = check_indent("ROOK", EXPECTED_INDENTS["character"])
                if char_ok:
                    score += 15
                    feedback.append("Character name indentation correct")
                else:
                    feedback.append(f"Character name indentation incorrect ({char_msg})")

                # 3b. Dialogue Indent ("You look like hell") - L:1.0" (1440), R:1.5" (2160)
                dial_ok, dial_msg = check_indent("You look like hell", EXPECTED_INDENTS["dialogue_left"], EXPECTED_INDENTS["dialogue_right"])
                if dial_ok:
                    score += 15
                    feedback.append("Dialogue indentation correct")
                else:
                    feedback.append(f"Dialogue indentation incorrect ({dial_msg})")

                # 3c. Parenthetical Indent ("rubbing his eyes") - L:1.5" (2160)
                paren_ok, paren_msg = check_indent("rubbing his eyes", EXPECTED_INDENTS["parenthetical"])
                if paren_ok:
                    score += 10
                    feedback.append("Parenthetical indentation correct")
                else:
                    feedback.append(f"Parenthetical indentation incorrect ({paren_msg})")
                
                # --- Criterion 4: File Exists bonus (20 pts) ---
                # Already checked existence, give points for formatting + existence
                score += 20
                
        except Exception as e:
            return {
                "passed": False, 
                "score": score, 
                "feedback": f"Error parsing output file: {str(e)}",
                "details": feedback
            }

        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback)
        }