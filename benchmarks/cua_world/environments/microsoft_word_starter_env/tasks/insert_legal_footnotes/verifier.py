#!/usr/bin/env python3
"""
Verifier for insert_legal_footnotes task.

Verification Strategy:
1. XML Verification (Primary):
   - Unzip the .docx file
   - Check 'word/footnotes.xml' for the presence of the 4 specific citations.
   - Check 'word/document.xml' to ensure the placeholder markers ([FN1] etc.) are gone.
2. Timestamp Verification:
   - Ensure the file was modified after task start time.
"""

import json
import logging
import os
import shutil
import tempfile
import zipfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insert_legal_footnotes(traj, env_info, task_info):
    """
    Verify that footnotes were inserted and markers removed in the Word document.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    remote_json_path = "C:\\workspace\\task_result.json"
    remote_doc_path = task_info['metadata']['target_file']
    
    # Temp setup
    temp_dir = tempfile.mkdtemp()
    local_json_path = os.path.join(temp_dir, "task_result.json")
    local_doc_path = os.path.join(temp_dir, "Legal_Memo.docx")

    try:
        # 1. Retrieve Result JSON
        try:
            copy_from_env(remote_json_path, local_json_path)
            with open(local_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task result JSON: {str(e)}"
            }

        # 2. Check File modification
        if not result_data.get('is_modified', False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Document was not saved/modified after task start. Score: 0/100"
            }

        # 3. Retrieve Document
        try:
            copy_from_env(remote_doc_path, local_doc_path)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Could not retrieve document file. Did you save it?"
            }

        if not zipfile.is_zipfile(local_doc_path):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Saved file is not a valid Word document (.docx)."
            }

        # 4. XML Parsing and Verification
        score = 10 # Base score for saving valid file
        feedback_parts = ["File saved successfully (+10)"]
        
        with zipfile.ZipFile(local_doc_path, 'r') as zf:
            # Check footnotes.xml
            try:
                footnotes_xml = zf.read('word/footnotes.xml').decode('utf-8')
            except KeyError:
                footnotes_xml = ""
                feedback_parts.append("No footnotes found in document.")

            # Check document.xml (body text)
            try:
                document_xml = zf.read('word/document.xml').decode('utf-8')
            except KeyError:
                return {"passed": False, "score": 10, "feedback": "Corrupt document: missing word/document.xml"}

        # Verify Citations (Footnotes)
        citations = task_info['metadata']['expected_citations']
        # FN1: Hadley v. Baxendale
        # FN2: 2-715
        # FN3: Restatement (Second) of Contracts
        # FN4: Sullivan v. O'Connor

        for key, text in citations.items():
            if text in footnotes_xml:
                score += 20
                feedback_parts.append(f"Footnote {key} verified (+20)")
            else:
                feedback_parts.append(f"Footnote {key} missing or incorrect text.")

        # Verify Marker Removal
        # Markers should NOT be in document.xml (they are moved to footnotes.xml or deleted)
        markers_present = []
        for marker in ["[FN1]", "[FN2]", "[FN3]", "[FN4]"]:
            if marker in document_xml:
                markers_present.append(marker)
        
        if not markers_present:
            score += 10
            feedback_parts.append("All body text markers removed (+10)")
        else:
            feedback_parts.append(f"Markers still present in body: {', '.join(markers_present)}")

        # Final Evaluation
        passed = score >= 60
        feedback = "; ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)