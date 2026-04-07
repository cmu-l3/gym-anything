#!/usr/bin/env python3
"""
Verifier for Insert SmartArt Process Diagram task.

VERIFICATION STRATEGY:
1. File Existence & Anti-Gaming:
   - Check if 'incident_management_process.docx' exists.
   - Verify it was modified AFTER the task started (prevents using pre-made files).

2. SmartArt Verification (XML Parsing):
   - DOCX files are ZIP archives. We extract them to inspect internal structure.
   - SmartArt diagrams are stored in the 'word/diagrams/' folder (e.g., data1.xml).
   - We check for the existence of this folder (proves SmartArt usage vs plain text).
   - We parse the XML to find the required labels ("Identify", "Log", etc.).

3. Document Content Verification:
   - Parse 'word/document.xml' to verify Title (Heading 1), Subtitle (Heading 2),
     and the numbered list content.

Scoring:
- 100 points total
- Pass threshold: 60 points (Must have SmartArt)
"""

import json
import os
import sys
import tempfile
import zipfile
import re
import logging
from xml.etree import ElementTree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values
REQUIRED_LABELS = ["Identify", "Log", "Diagnose", "Resolve", "Close"]
REQUIRED_TITLE = "IT Incident Management Process"
REQUIRED_SUBTITLE = "Standard Operating Procedure"
REQUIRED_BODY_PHRASE = "five-stage incident management process"
RESULT_FILENAME = "insert_smartart_process_diagram_result.json"
DOC_FILENAME = "incident_management_process.docx"

def verify_insert_smartart_process_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp()
    score = 0
    feedback_parts = []
    
    try:
        # 1. Fetch Result JSON
        local_result_json = os.path.join(temp_dir, RESULT_FILENAME)
        try:
            copy_from_env(f"C:\\Users\\Docker\\{RESULT_FILENAME}", local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # Check basic file existence and timestamps
        if not result_data.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Output file 'incident_management_process.docx' was not found."}
        
        if not result_data.get("file_created_during_task"):
            return {"passed": False, "score": 0, "feedback": "Output file was not created or modified during the task session."}
        
        score += 10 # File exists and is new
        feedback_parts.append("File created successfully")

        # 2. Fetch Document
        local_docx = os.path.join(temp_dir, DOC_FILENAME)
        try:
            copy_from_env(result_data.get("output_path", ""), local_docx)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"File exists but could not be downloaded: {str(e)}"}

        # 3. Verify DOCX Structure (XML Parsing)
        try:
            with zipfile.ZipFile(local_docx, 'r') as z:
                file_list = z.namelist()
                
                # Check for SmartArt folder structure
                # SmartArt typically creates 'word/diagrams/data1.xml', 'drawing1.xml', etc.
                diagram_files = [f for f in file_list if f.startswith('word/diagrams/data')]
                
                has_smartart = len(diagram_files) > 0
                smartart_labels_found = set()
                
                if has_smartart:
                    score += 20
                    feedback_parts.append("SmartArt object detected")
                    
                    # Inspect SmartArt Content
                    for d_file in diagram_files:
                        xml_content = z.read(d_file).decode('utf-8', errors='ignore')
                        # SmartArt text is often in <dgm:t> or similar tags, but plain string search is robust enough for verification
                        for label in REQUIRED_LABELS:
                            if label in xml_content:
                                smartart_labels_found.add(label)
                    
                    # Also check drawing xmls if data xmls missed it (sometimes text is in drawing1.xml)
                    if len(smartart_labels_found) < len(REQUIRED_LABELS):
                        drawing_files = [f for f in file_list if f.startswith('word/diagrams/drawing')]
                        for d_file in drawing_files:
                            xml_content = z.read(d_file).decode('utf-8', errors='ignore')
                            for label in REQUIRED_LABELS:
                                if label in xml_content:
                                    smartart_labels_found.add(label)

                    found_count = len(smartart_labels_found)
                    if found_count == len(REQUIRED_LABELS):
                        score += 30 # All labels found in diagram
                        feedback_parts.append("All 5 diagram steps labeled correctly")
                    elif found_count > 0:
                        partial = int(30 * (found_count / 5))
                        score += partial
                        feedback_parts.append(f"Found {found_count}/5 diagram labels")
                    else:
                        feedback_parts.append("Diagram found but labels are missing or incorrect")
                else:
                    feedback_parts.append("No SmartArt diagram detected (Missing 'word/diagrams/' structure)")

                # Check Document Text and Styles (word/document.xml)
                if 'word/document.xml' in file_list:
                    doc_xml = z.read('word/document.xml').decode('utf-8', errors='ignore')
                    
                    # Check Heading 1 Title
                    # Looking for pattern: <w:pStyle w:val="Heading1"/> ... <w:t>IT Incident Management Process</w:t>
                    # Regex is safer to span tags
                    if "Heading1" in doc_xml and REQUIRED_TITLE in doc_xml:
                        score += 10
                        feedback_parts.append("Title with Heading 1 found")
                    elif REQUIRED_TITLE in doc_xml:
                        score += 5
                        feedback_parts.append("Title text found (style check loose)")
                    else:
                        feedback_parts.append("Title missing")

                    # Check Heading 2 Subtitle
                    if "Heading2" in doc_xml and REQUIRED_SUBTITLE in doc_xml:
                        score += 5
                        feedback_parts.append("Subtitle with Heading 2 found")
                    
                    # Check Introduction
                    if REQUIRED_BODY_PHRASE in doc_xml:
                        score += 10
                        feedback_parts.append("Introduction paragraph found")

                    # Check Numbered List
                    # We verify the presence of the description text. 
                    # Checking actual "numbering" structure in XML (<w:numPr>) is complex, 
                    # so we'll accept text presence + context.
                    list_items = ["Detect and report", "incident details", "Investigate root cause", "Implement a fix", "Confirm resolution"]
                    found_items = 0
                    for item in list_items:
                        if item in doc_xml:
                            found_items += 1
                    
                    if found_items >= 4:
                        score += 15
                        feedback_parts.append("Process descriptions list found")
                    elif found_items > 0:
                        score += 5
                        feedback_parts.append("Partial process descriptions found")

        except zipfile.BadZipFile:
            return {"passed": False, "score": 0, "feedback": "Saved file is not a valid DOCX (ZIP) archive."}

    except Exception as e:
        logger.exception("Verification error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir)

    # Pass logic
    # Must have file (10), SmartArt (20), and at least some correct labels/content
    # Threshold 60 ensures they didn't just type text (which would cap at ~40 points for text/headings)
    passed = score >= 60 and ("SmartArt object detected" in feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }