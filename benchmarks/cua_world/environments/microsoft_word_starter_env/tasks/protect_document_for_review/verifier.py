#!/usr/bin/env python3
"""
Verifier for Microsoft Word document protection task.
"""

import json
import os
import zipfile
import tempfile
import logging
from xml.dom import minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_protect_document(traj, env_info, task_info):
    """
    Verifies that:
    1. The document exists and was modified during the task.
    2. Document protection is enabled with type="comments".
    3. Protection is enforced (password hash present).
    4. An editing exception ("everyone") exists for the specific section.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Scoring weights
    SCORE_FILE_MODIFIED = 10
    SCORE_PROTECTION_TYPE = 30
    SCORE_ENFORCED = 20
    SCORE_PASSWORD = 15
    SCORE_EXCEPTION = 25
    
    score = 0
    feedback_parts = []
    
    # Temp paths
    temp_dir = tempfile.mkdtemp()
    local_json_path = os.path.join(temp_dir, "task_result.json")
    local_doc_path = os.path.join(temp_dir, "submission.docx")
    
    try:
        # 1. Read Basic Result Metadata
        try:
            copy_from_env("C:\\task_result.json", local_json_path)
            with open(local_json_path, 'r') as f:
                res_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
            
        if not res_data.get("file_exists"):
            return {"passed": False, "score": 0, "feedback": "Document file was not saved."}
            
        if not res_data.get("file_created_during_task"):
            # If file wasn't modified, they didn't save their changes
            return {"passed": False, "score": 0, "feedback": "Document was not modified/saved after task start."}
        
        score += SCORE_FILE_MODIFIED
        feedback_parts.append("File saved successfully")

        # 2. Inspect DOCX Internals
        try:
            copy_from_env(res_data["output_path"], local_doc_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Could not retrieve document for inspection: {e}"}

        if not zipfile.is_zipfile(local_doc_path):
             return {"passed": False, "score": score, "feedback": "Saved file is not a valid DOCX."}

        with zipfile.ZipFile(local_doc_path, 'r') as doc_zip:
            
            # --- Check settings.xml for Protection ---
            try:
                settings_xml = doc_zip.read('word/settings.xml')
                settings_dom = minidom.parseString(settings_xml)
                
                # Look for <w:documentProtection>
                protection_nodes = settings_dom.getElementsByTagName('w:documentProtection')
                
                if not protection_nodes:
                    feedback_parts.append("FAIL: No document protection settings found.")
                else:
                    node = protection_nodes[0]
                    edit_type = node.getAttribute('w:edit')
                    enforcement = node.getAttribute('w:enforcement')
                    
                    # Word 2010 uses specific attributes for password hash
                    # Usually w:cryptAlgorithmSid, w:hash, w:salt, etc. OR w:password in older compat modes
                    # We just check if ANY hash attribute is present to confirm a password was set
                    has_password = (node.hasAttribute('w:cryptProviderType') or 
                                    node.hasAttribute('w:hash') or 
                                    node.hasAttribute('w:cryptAlgorithmSid'))

                    # Verify Type
                    if edit_type == "comments":
                        score += SCORE_PROTECTION_TYPE
                        feedback_parts.append("Protection type 'Comments' correct")
                    else:
                        feedback_parts.append(f"FAIL: Wrong protection type (found '{edit_type}', expected 'comments')")

                    # Verify Enforcement
                    if enforcement == "1" or enforcement == "true":
                        score += SCORE_ENFORCED
                        feedback_parts.append("Protection enforced")
                    else:
                        feedback_parts.append("FAIL: Protection not enforced")
                        
                    # Verify Password
                    if has_password:
                        score += SCORE_PASSWORD
                        feedback_parts.append("Password set")
                    else:
                        feedback_parts.append("FAIL: No password set")

            except KeyError:
                feedback_parts.append("FAIL: word/settings.xml missing from docx")
            
            # --- Check document.xml for Permissions (Exceptions) ---
            try:
                doc_xml = doc_zip.read('word/document.xml')
                doc_dom = minidom.parseString(doc_xml)
                
                # Look for <w:permStart w:edGrp="everyone" ...>
                # This tag marks the start of an editable region for "everyone"
                perm_starts = doc_dom.getElementsByTagName('w:permStart')
                has_exception = False
                
                for perm in perm_starts:
                    if perm.getAttribute('w:edGrp') == "everyone":
                        has_exception = True
                        break
                
                if has_exception:
                    score += SCORE_EXCEPTION
                    feedback_parts.append("Editing exception for 'Everyone' found")
                else:
                    feedback_parts.append("FAIL: No editing exception found for 'Everyone'")

            except KeyError:
                feedback_parts.append("FAIL: word/document.xml missing")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        try:
            import shutil
            shutil.rmtree(temp_dir)
        except:
            pass

    # Success determination
    # Must have protection type correct and enforced to pass at all
    critical_criteria_met = ("Protection type 'Comments' correct" in feedback_parts and 
                             "Protection enforced" in feedback_parts)
    
    passed = (score >= 75) and critical_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }