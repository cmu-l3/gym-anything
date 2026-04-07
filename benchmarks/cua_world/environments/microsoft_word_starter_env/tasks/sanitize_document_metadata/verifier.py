#!/usr/bin/env python3
"""
Verifier for Sanitize Document Metadata task.

Verification Steps:
1. Check if 'Final_Public_Release.docx' exists and was saved during the task.
2. Parse the DOCX internal XML.
3. Verify Tracked Changes: <w:ins> and <w:del> counts should be 0.
4. Verify Comments: word/comments.xml should not exist or be empty.
5. Verify Metadata: docProps/core.xml should not contain 'Internal Reviewer'.
6. Verify Content: Ensure the text matches the expected 'clean' state (changes accepted).
"""

import json
import logging
import os
import zipfile
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
RESULT_JSON_PATH = "C:\\Users\\Docker\\sanitize_document_metadata_result.json"
OUTPUT_DOCX_PATH = "C:\\Users\\Docker\\Documents\\Final_Public_Release.docx"

def verify_sanitize_document_metadata(traj, env_info, task_info):
    """
    Verifies that the document was properly sanitized.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp directory for processing
    with tempfile.TemporaryDirectory() as temp_dir:
        local_result_json = os.path.join(temp_dir, "result.json")
        local_docx = os.path.join(temp_dir, "Final_Public_Release.docx")

        # 1. Copy Result JSON
        try:
            copy_from_env(RESULT_JSON_PATH, local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy/read result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Could not retrieve task status. Did you save the file?"}

        # Check basic file existence
        if not result_data.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "The file 'Final_Public_Release.docx' was not found."}
        
        if not result_data.get('file_created_during_task', False):
            return {"passed": False, "score": 0, "feedback": "The output file was not modified during the task session."}

        # 2. Copy DOCX file
        try:
            copy_from_env(OUTPUT_DOCX_PATH, local_docx)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve document: {e}"}

        if not zipfile.is_zipfile(local_docx):
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid DOCX."}

        # 3. Analyze XML Content
        score = 10 # Base points for saving the file
        feedback = ["File saved successfully."]
        passed = False
        
        try:
            with zipfile.ZipFile(local_docx, 'r') as zf:
                
                # --- CHECK A: Tracked Changes (w:ins / w:del) ---
                try:
                    doc_xml = zf.read('word/document.xml').decode('utf-8')
                    
                    # Count insertions and deletions
                    ins_count = len(re.findall(r'<w:ins\b', doc_xml))
                    del_count = len(re.findall(r'<w:del\b', doc_xml))
                    
                    if ins_count == 0 and del_count == 0:
                        score += 25
                        feedback.append("Success: All tracked changes accepted.")
                    else:
                        feedback.append(f"Fail: Found {ins_count} insertions and {del_count} deletions remaining. You must accept all changes.")
                        
                    # Check Content Correctness (Clean text check)
                    # "views" should be present, "considers" should be absent
                    if "views" in doc_xml and "considers" not in doc_xml:
                        score += 15
                        feedback.append("Success: Content matches expected clean state.")
                    else:
                        feedback.append("Fail: Content does not match expected state (did you reject changes instead of accepting?).")
                        
                except Exception as e:
                    feedback.append(f"Error reading document body: {e}")

                # --- CHECK B: Comments ---
                try:
                    # comments.xml usually doesn't exist if no comments, or is empty/stub
                    comment_xml_exists = 'word/comments.xml' in zf.namelist()
                    if not comment_xml_exists:
                        score += 25
                        feedback.append("Success: No comments file found (Comments removed).")
                    else:
                        comments_xml = zf.read('word/comments.xml').decode('utf-8')
                        # Check if there are actual comments inside
                        comment_count = len(re.findall(r'<w:comment\b', comments_xml))
                        if comment_count == 0:
                            score += 25
                            feedback.append("Success: Comments file is empty.")
                        else:
                            feedback.append(f"Fail: Found {comment_count} comments remaining.")
                except Exception as e:
                    feedback.append(f"Error checking comments: {e}")

                # --- CHECK C: Metadata (Author/Creator) ---
                try:
                    core_xml = zf.read('docProps/core.xml').decode('utf-8')
                    
                    # Regex to find creator/lastModifiedBy
                    # <dc:creator>Internal Reviewer</dc:creator>
                    creator_match = re.search(r'<dc:creator>(.*?)</dc:creator>', core_xml)
                    modifier_match = re.search(r'<cp:lastModifiedBy>(.*?)</cp:lastModifiedBy>', core_xml)
                    
                    creator = creator_match.group(1) if creator_match else ""
                    modifier = modifier_match.group(1) if modifier_match else ""
                    
                    dirty_terms = ["Internal Reviewer", "Chief of Staff"]
                    
                    is_clean = True
                    for term in dirty_terms:
                        if term in creator or term in modifier:
                            is_clean = False
                            break
                    
                    # Also stricter check: should be empty or default "Microsoft Office User" or similar?
                    # The task inspect document feature often removes the tag or sets it to empty.
                    
                    if is_clean:
                        score += 25
                        feedback.append("Success: Personal metadata removed.")
                    else:
                        feedback.append(f"Fail: Author metadata still contains '{creator}' or '{modifier}'.")
                        
                except KeyError:
                    # docProps/core.xml might be missing if scrubbed completely?
                    score += 25
                    feedback.append("Success: Metadata properties missing (Scrubbed).")
                except Exception as e:
                    feedback.append(f"Error checking metadata: {e}")

        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error analyzing DOCX structure: {e}"}

        # Calculate final pass/fail
        passed = score >= 85
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }