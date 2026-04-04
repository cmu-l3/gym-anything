#!/usr/bin/env python3
"""
Verifier for menu_tab_formatting task.
Verifies correct application of styles, alignment, tab stops with dot leaders, and italics.
"""

import json
import os
import sys
import tempfile
import logging

# Add utils path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    vlm_verify_screenshot
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants for validation
# 1 inch = 914400 EMU
MIN_TAB_POS_EMU = 3657600  # 4 inches (generous tolerance, target is ~6 inches)
DOT_LEADER_TYPES = [1, 2, 4]  # WD_TAB_LEADER: DOTS(1), MIDDLE_DOT(2), HEAVY(4) - allowing variations


def verify_menu_formatting(traj, env_info, task_info):
    """
    Verify the formatted restaurant menu.
    
    Criteria:
    1. Output file exists and was modified during task.
    2. Header text is Centered.
    3. Category headings use "Heading 2" style.
    4. Menu items use Right-Aligned Tab Stops.
    5. Tab stops use Dot Leaders.
    6. Descriptions are on separate lines and Italicized.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Load task result metadata
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            task_result = json.load(f)
    except Exception:
        return {"passed": False, "score": 0, "feedback": "Could not load task execution results"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'menu_formatted.docx' not found."}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task."}

    # Load the DOCX file
    output_path = "/home/ga/Documents/menu_formatted.docx"
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse output document: {error}"}

    try:
        score = 0
        feedback = []
        max_score = 100
        
        # --- 1. Check Header Alignment (10 pts) ---
        # First paragraph should be "HARTWELL'S..." and CENTERED (WD_ALIGN_PARAGRAPH.CENTER=1)
        header_ok = False
        if len(doc.paragraphs) > 0:
            para = doc.paragraphs[0]
            # Alignment can be None (default/left), 0 (left), 1 (center), 2 (right), 3 (justify)
            # Or inherited from style. But usually direct formatting is applied for this task.
            align = para.alignment
            if align == 1: # CENTER
                header_ok = True
                score += 10
                feedback.append("Header is centered.")
            else:
                feedback.append(f"Header alignment incorrect (expected Center).")
        
        # --- 2. Check Category Headings (15 pts) ---
        categories = ["Starters", "Soups", "Entrées", "Sides", "Desserts", "Beverages"]
        cats_found = 0
        cats_styled = 0
        
        for para in doc.paragraphs:
            text = para.text.strip()
            # Loose matching for categories
            if any(cat in text for cat in categories) and len(text) < 30:
                cats_found += 1
                if para.style and "Heading 2" in para.style.name:
                    cats_styled += 1
        
        if cats_styled >= 4: # Allow some misses
            score += 15
            feedback.append(f"Category headings styled correctly ({cats_styled} found).")
        elif cats_styled > 0:
            score += 7
            feedback.append(f"Some category headings styled ({cats_styled}).")
        else:
            feedback.append("Category headings missing 'Heading 2' style.")

        # --- 3. Check Tab Stops & Dot Leaders (30 pts) ---
        # Look for paragraphs with tab stops
        tab_paragraphs = 0
        right_aligned_tabs = 0
        dot_leaders = 0
        
        # python-docx constants
        # WD_TAB_ALIGNMENT.RIGHT = 2
        # WD_TAB_LEADER.DOTS = 1
        
        for para in doc.paragraphs:
            if not para.paragraph_format.tab_stops:
                continue
            
            has_right_tab = False
            has_dot = False
            
            for tab in para.paragraph_format.tab_stops:
                # Check alignment (2 is Right)
                if tab.alignment == 2:
                    has_right_tab = True
                    # Check position (sanity check, e.g. > 4 inches)
                    if tab.position and tab.position > MIN_TAB_POS_EMU:
                        # Check leader
                        if tab.leader in DOT_LEADER_TYPES: 
                            has_dot = True
            
            if has_right_tab:
                right_aligned_tabs += 1
            if has_dot:
                dot_leaders += 1

        # Scoring Tabs
        if right_aligned_tabs >= 10: # Reasonable number of menu items
            score += 15
            feedback.append(f"Right-aligned tabs used ({right_aligned_tabs} items).")
        elif right_aligned_tabs > 0:
            score += 5
            feedback.append("Few right-aligned tabs found.")
        else:
            feedback.append("No right-aligned tabs found.")

        # Scoring Leaders
        if dot_leaders >= 10:
            score += 15
            feedback.append("Dot leaders applied correctly.")
        elif dot_leaders > 0:
            score += 5
            feedback.append("Few dot leaders found.")
        else:
            feedback.append("No dot leaders found.")

        # --- 4. Check Italics & Descriptions (20 pts) ---
        # We expect descriptions to be on their own lines now (no longer containing prices)
        # and to be italicized.
        italic_lines = 0
        
        for para in doc.paragraphs:
            text = para.text.strip()
            if not text: continue
            
            # Skip likely headings or items with prices
            if "$" in text or any(cat in text for cat in categories):
                continue
                
            # Check if this paragraph is fully italic
            # Logic: All runs are italic, or style is italic
            is_italic = False
            
            # Check style
            if para.style and para.style.font and para.style.font.italic:
                is_italic = True
            
            # Check runs if not styled
            if not is_italic and para.runs:
                # If all runs that have text are italic
                runs_italic = True
                has_text_runs = False
                for run in para.runs:
                    if run.text.strip():
                        has_text_runs = True
                        if not run.italic:
                            runs_italic = False
                            break
                if has_text_runs and runs_italic:
                    is_italic = True
            
            if is_italic:
                italic_lines += 1

        if italic_lines >= 10:
            score += 20
            feedback.append(f"Descriptions moved and italicized ({italic_lines} lines).")
        elif italic_lines > 0:
            score += 10
            feedback.append("Some italic descriptions found.")
        else:
            feedback.append("Descriptions not italicized or not moved to new lines.")

        # --- 5. Output File Existence & Validity (10 pts) ---
        score += 10 # Base points for valid file if we got this far

        # --- 6. VLM Verification (10 pts) ---
        # Visual check for structure
        final_score = score
        vlm_success = False
        
        vlm_res = vlm_verify_screenshot(env_info, traj, 
            "Analyze this menu document. Does it look formatted? "
            "1. Is there a centered header? "
            "2. Are prices aligned to the right? "
            "3. Are there dot leaders (.....) connecting items to prices? "
            "Return JSON: {'formatted_header': bool, 'dot_leaders_visible': bool}"
        )
        
        if vlm_res and vlm_res.get('parsed'):
            parsed = vlm_res['parsed']
            if parsed.get('formatted_header') and parsed.get('dot_leaders_visible'):
                final_score += 10
                feedback.append("Visual verification passed.")
                vlm_success = True
            else:
                feedback.append("Visual verification: Layout features not clearly visible.")

        passed = (final_score >= 60) and (right_aligned_tabs > 0 or vlm_success)

        return {
            "passed": passed,
            "score": min(100, final_score),
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)