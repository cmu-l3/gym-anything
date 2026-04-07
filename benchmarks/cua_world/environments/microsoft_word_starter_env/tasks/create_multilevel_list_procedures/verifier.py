#!/usr/bin/env python3
"""
Verifier for create_multilevel_list_procedures task.

Verifies:
1. File creation and freshness (Anti-gaming)
2. Document content (Title and hierarchical items)
3. Document structure (XML parsing for list levels)
4. List formatting (Validating multi-level list usage)
"""

import json
import logging
import os
import re
import shutil
import tempfile
import zipfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
RESULT_JSON_PATH = "C:\\temp\\task_result.json"
DOCX_PATH = "C:\\Users\\Docker\\Documents\\Emergency_Response_Procedures.docx"

def verify_create_multilevel_list_procedures(traj, env_info, task_info):
    """
    Verify the creation of a multi-level list document in Word.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    required_level1 = metadata.get("required_content", {}).get("level1", [])
    required_level2 = metadata.get("required_content", {}).get("level2", [])
    required_level3 = metadata.get("required_content", {}).get("level3", [])

    tmp_dir = tempfile.mkdtemp(prefix="verify_word_task_")
    try:
        # --- Step 1: Check Metadata & File Existence (20 pts) ---
        local_result_json = os.path.join(tmp_dir, "task_result.json")
        try:
            copy_from_env(RESULT_JSON_PATH, local_result_json)
            with open(local_result_json, "r") as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        score = 0
        feedback = []

        if not result_data.get("file_exists", False):
            return {"passed": False, "score": 0, "feedback": "FAIL: Output file not found."}
        
        score += 10
        feedback.append("File exists")

        if not result_data.get("is_new_file", False):
            feedback.append("WARNING: File timestamps indicate it wasn't modified during task.")
        else:
            score += 10
            feedback.append("File created/modified during task")

        # --- Step 2: Retrieve and Parse Document (Content: 40 pts, Formatting: 40 pts) ---
        local_docx = os.path.join(tmp_dir, "document.docx")
        try:
            copy_from_env(DOCX_PATH, local_docx)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to copy document: {e}"}

        if not zipfile.is_zipfile(local_docx):
            return {"passed": False, "score": score, "feedback": "File is not a valid DOCX archive."}

        try:
            with zipfile.ZipFile(local_docx, 'r') as zf:
                xml_content = zf.read('word/document.xml').decode('utf-8')
                
                # Try reading numbering.xml for extra credit/robustness
                try:
                    numbering_xml = zf.read('word/numbering.xml').decode('utf-8')
                    has_numbering_def = True
                except KeyError:
                    has_numbering_def = False
                    numbering_xml = ""

        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse DOCX XML: {e}"}

        # --- Content Verification (40 pts) ---
        # Normalize XML content to text for simple existence checks
        # NOTE: This simple regex removes tags to find text. 
        # For structure checks, we need to look at specific paragraphs.
        
        # Helper to extract paragraphs with their list properties
        # Pattern looks for: <w:p> ... <w:numPr> ... <w:ilvl w:val="X"/> ... <w:t>Content</w:t> ... </w:p>
        # This is complex to regex perfectly, so we do a two-pass approach.
        # 1. Find all paragraph blocks
        # 2. Analyze each block for content and level
        
        paragraphs = re.findall(r'<w:p[ >].*?</w:p>', xml_content, re.DOTALL)
        
        found_l1 = 0
        found_l2 = 0
        found_l3 = 0
        
        # Tracking structure correctness
        valid_structure_count = 0
        
        for p in paragraphs:
            # Extract text content from this paragraph
            text_parts = re.findall(r'<w:t[^>]*>(.*?)</w:t>', p)
            full_text = "".join(text_parts).strip()
            
            # Check level
            ilvl_match = re.search(r'<w:ilvl w:val="(\d+)"/>', p)
            num_id_match = re.search(r'<w:numId w:val="(\d+)"/>', p)
            
            current_level = -1
            if ilvl_match and num_id_match:
                current_level = int(ilvl_match.group(1))

            # Verify items
            if full_text in required_level1:
                found_l1 += 1
                if current_level == 0: valid_structure_count += 1
            elif full_text in required_level2:
                found_l2 += 1
                if current_level == 1: valid_structure_count += 1
            elif full_text in required_level3:
                found_l3 += 1
                if current_level == 2: valid_structure_count += 1

        # Score Content Presence
        content_score = 0
        if found_l1 == len(required_level1): content_score += 10
        if found_l2 == len(required_level2): content_score += 15
        if found_l3 >= 15: content_score += 15  # Allow missing 1-2 items for minor typos
        
        score += content_score
        feedback.append(f"Content Score: {content_score}/40 (L1:{found_l1}, L2:{found_l2}, L3:{found_l3})")

        # --- Structure & Formatting Verification (40 pts) ---
        # 1. Title Existence (5 pts)
        if "Office Emergency Response Procedures" in xml_content:
            score += 5
            feedback.append("Title found")
        
        # 2. Multi-level List Usage (20 pts)
        # We need to see distinct levels (0, 1, 2) being used with numbering properties
        distinct_levels_used = set()
        for p in paragraphs:
             ilvl = re.search(r'<w:ilvl w:val="(\d+)"/>', p)
             numid = re.search(r'<w:numId w:val="(\d+)"/>', p)
             if ilvl and numid:
                 distinct_levels_used.add(int(ilvl.group(1)))
        
        if 0 in distinct_levels_used and 1 in distinct_levels_used and 2 in distinct_levels_used:
            score += 20
            feedback.append("Correct multi-level structure detected (Levels 0, 1, 2 used)")
        elif len(distinct_levels_used) >= 2:
             score += 10
             feedback.append(f"Partial structure detected (Levels: {distinct_levels_used})")
        
        # 3. Legal Style Numbering (15 pts)
        # Check numbering.xml for the pattern "%1.%2" or "%1.%2.%3"
        legal_style_found = False
        if has_numbering_def:
            # Legal style typically uses w:lvlText with multiple levels like "%1.%2"
            if '%1.%2' in numbering_xml:
                legal_style_found = True
        
        if legal_style_found:
            score += 15
            feedback.append("Legal-style numbering definition found")
        else:
            feedback.append("Legal-style numbering definition NOT found (or standard bullet/numbering used)")

        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)