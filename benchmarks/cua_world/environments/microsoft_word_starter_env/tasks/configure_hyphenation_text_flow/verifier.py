#!/usr/bin/env python3
"""
Verifier for configure_hyphenation_text_flow task.

Verification Strategy:
1. Validate file creation and modification (anti-gaming).
2. Inspect OOXML (zip) content of the .docx file:
   - word/settings.xml: Check <w:autoHyphenation> and <w:consecutiveHyphenLimit>
   - word/document.xml: Check justification (<w:jc w:val="both">)
   - word/document.xml: Check <w:keepLines> on specific paragraph
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

# Constants matching Windows environment paths
RESULT_PATH = "C:\\Users\\Docker\\task_result.json"
OUTPUT_DOC_PATH = "C:\\Users\\Docker\\Documents\\NIST_Report_Final.docx"

def verify_configure_hyphenation_text_flow(traj, env_info, task_info):
    """
    Verify the hyphenation and text flow settings in the Word document.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    hyphen_limit_target = metadata.get("hyphen_limit", 2)
    target_paragraph_start = metadata.get("target_paragraph_start", "Risk management is the ongoing process")

    # Temporary directory for analysis
    tmp_dir = tempfile.mkdtemp(prefix="verify_hyphen_")
    
    try:
        # 1. Retrieve Result JSON
        local_result_json = os.path.join(tmp_dir, "result.json")
        try:
            copy_from_env(RESULT_PATH, local_result_json)
            with open(local_result_json, "r") as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check basic file requirements
        if not result_data.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Output file 'NIST_Report_Final.docx' was not found."}
        
        if not result_data.get("file_created_during_task", False):
            return {"passed": False, "score": 0, "feedback": "The output file was not modified during the task session."}

        # 2. Retrieve Document
        local_docx = os.path.join(tmp_dir, "NIST_Report_Final.docx")
        try:
            copy_from_env(OUTPUT_DOC_PATH, local_docx)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve output document: {e}"}

        # 3. Analyze OOXML
        if not zipfile.is_zipfile(local_docx):
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid DOCX archive."}

        score = 0
        feedback = []
        
        with zipfile.ZipFile(local_docx, 'r') as zf:
            # --- Check Hyphenation Settings (word/settings.xml) ---
            try:
                settings_xml = zf.read("word/settings.xml").decode("utf-8")
                
                # Check Auto Hyphenation
                if re.search(r'<w:autoHyphenation(?: w:val="true"|/)?>', settings_xml):
                    score += 30
                    feedback.append("Pass: Automatic Hyphenation is enabled (30/30).")
                else:
                    feedback.append("Fail: Automatic Hyphenation not enabled.")

                # Check Consecutive Hyphen Limit
                # Look for <w:consecutiveHyphenLimit w:val="2"/>
                limit_match = re.search(r'<w:consecutiveHyphenLimit w:val="(\d+)"', settings_xml)
                if limit_match and int(limit_match.group(1)) == hyphen_limit_target:
                    score += 20
                    feedback.append(f"Pass: Consecutive hyphen limit set to {hyphen_limit_target} (20/20).")
                else:
                    val = limit_match.group(1) if limit_match else "None"
                    feedback.append(f"Fail: Consecutive hyphen limit incorrect. Found: {val}, Expected: {hyphen_limit_target}.")

            except KeyError:
                feedback.append("Fail: word/settings.xml not found in document.")

            # --- Check Text Justification and Keep Lines Together (word/document.xml) ---
            try:
                doc_xml = zf.read("word/document.xml").decode("utf-8")
                
                # Check Justification (Sampling paragraphs)
                # We look for <w:jc w:val="both"/> (Word uses 'both' for justify)
                # Ideally, many paragraphs should have this.
                jc_matches = len(re.findall(r'<w:jc w:val="both"', doc_xml))
                if jc_matches >= 3: # At least a few paragraphs
                    score += 20
                    feedback.append("Pass: Text justification applied to multiple paragraphs (20/20).")
                elif jc_matches > 0:
                    score += 10
                    feedback.append("Partial: Text justification found but applied sparsely (10/20).")
                else:
                    feedback.append("Fail: Justified text alignment not found.")

                # Check "Keep lines together" on specific paragraph
                # Strategy: Find the text, then look backwards for the nearest <w:p> tag and its <w:pPr> properties
                # Simplified regex approach: Find <w:p>...<w:keepLines/>...Text...
                
                # Split xml into paragraphs <w:p>...</w:p>
                paragraphs = re.findall(r'<w:p[ >].*?</w:p>', doc_xml)
                target_found = False
                setting_correct = False
                
                for p in paragraphs:
                    if target_paragraph_start in p:
                        target_found = True
                        if "<w:keepLines" in p:
                            setting_correct = True
                        break
                
                if target_found and setting_correct:
                    score += 20
                    feedback.append("Pass: 'Keep lines together' applied to target paragraph (20/20).")
                elif target_found:
                    feedback.append("Fail: Target paragraph found but 'Keep lines together' not applied.")
                else:
                    feedback.append("Fail: Target paragraph text not found (content modified?).")

            except KeyError:
                feedback.append("Fail: word/document.xml not found.")

        # File saved bonus
        score += 10 # Base points for valid file save
        feedback.append("Pass: File saved correctly (10/10).")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        logger.exception("Verification failed with error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)