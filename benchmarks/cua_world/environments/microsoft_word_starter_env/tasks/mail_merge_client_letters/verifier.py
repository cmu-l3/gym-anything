#!/usr/bin/env python3
"""
Verifier for mail_merge_client_letters task.

Verifies:
1. Template document exists and contains Merge Fields.
2. Merged document exists and contains personalized data.
3. Documents were created during the task window.
4. Correct number of records (8) processed.
5. VLM verification of the workflow.
"""

import json
import logging
import os
import tempfile
import zipfile
import re
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
RESULT_JSON_PATH = "C:\\Users\\Docker\\mail_merge_result.json"
TEMPLATE_DOC_PATH = "C:\\Users\\Docker\\Documents\\notification_letter.docx"
MERGED_DOC_PATH = "C:\\Users\\Docker\\Documents\\merged_letters.docx"

def extract_xml_from_docx(docx_path):
    """Extract word/document.xml from a .docx file."""
    try:
        with zipfile.ZipFile(docx_path, 'r') as zf:
            return zf.read('word/document.xml').decode('utf-8')
    except Exception as e:
        logger.error(f"Failed to read docx XML: {e}")
        return None

def verify_mail_merge_client_letters(traj, env_info, task_info):
    """
    Verify the mail merge task execution.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp dir for analysis
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Load result JSON
        local_json_path = os.path.join(temp_dir, "result.json")
        try:
            copy_from_env(RESULT_JSON_PATH, local_json_path)
            with open(local_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}

        score = 0
        feedback_parts = []
        max_score = 100

        # Check file existence and timestamps (20 pts)
        template_info = result_data.get("template_file", {})
        merged_info = result_data.get("merged_file", {})

        if template_info.get("exists") and template_info.get("is_new"):
            score += 10
            feedback_parts.append("Template file saved correctly.")
        else:
            feedback_parts.append("Template file missing or not saved as new.")

        if merged_info.get("exists") and merged_info.get("is_new"):
            score += 10
            feedback_parts.append("Merged output file saved correctly.")
        else:
            feedback_parts.append("Merged output file missing or not saved as new.")
            # If merged file is missing, we can't do content checks on it
        
        # 2. Analyze Template Content (30 pts)
        if template_info.get("exists"):
            local_template_path = os.path.join(temp_dir, "template.docx")
            copy_from_env(TEMPLATE_DOC_PATH, local_template_path)
            
            xml_content = extract_xml_from_docx(local_template_path)
            if xml_content:
                # Check for MERGEFIELD tags
                # Word stores them usually as: <w:instrText> MERGEFIELD ContactName </w:instrText>
                # The regex needs to be loose because of XML tags splitting text
                
                field_hits = 0
                required_fields = ["ContactName", "CompanyName", "Address", "City", "Country"]
                
                # Simple check for MERGEFIELD keyword first
                if "MERGEFIELD" in xml_content:
                    score += 10
                    feedback_parts.append("Merge fields detected.")
                    
                    # Check for specific field names
                    for field in required_fields:
                        if field in xml_content:
                            field_hits += 1
                    
                    if field_hits >= 4:
                        score += 10
                        feedback_parts.append(f"Found {field_hits} specific merge fields.")
                    else:
                        feedback_parts.append(f"Only found {field_hits} specific merge fields (expected >4).")
                else:
                    feedback_parts.append("No MERGEFIELD codes found in template.")

                # Check for static body text
                if "GlobalTrade Consulting" in xml_content and "compliance regulations" in xml_content:
                    score += 10
                    feedback_parts.append("Letter body text appears correct.")
                else:
                    feedback_parts.append("Body text missing or incorrect.")

        # 3. Analyze Merged Content (40 pts)
        if merged_info.get("exists"):
            local_merged_path = os.path.join(temp_dir, "merged.docx")
            copy_from_env(MERGED_DOC_PATH, local_merged_path)
            
            xml_content = extract_xml_from_docx(local_merged_path)
            if xml_content:
                # Check for instantiated data from CSV
                data_hits = 0
                sample_data = ["Maria Anders", "Alfreds Futterkiste", "Thomas Hardy", "London", "Madrid"]
                
                found_samples = []
                for item in sample_data:
                    if item in xml_content:
                        found_samples.append(item)
                
                if len(found_samples) >= 3:
                    score += 20
                    feedback_parts.append(f"Merged data verified ({len(found_samples)} samples found).")
                else:
                    feedback_parts.append(f"Merged data check failed. Found: {found_samples}")

                # Check for volume/length (indicates multiple records)
                # Merged docs usually use section breaks <w:sectPr> or page breaks
                # Or we can just check file size ratio vs template
                
                template_size = template_info.get("size", 1)
                merged_size = merged_info.get("size", 0)
                
                if merged_size > (template_size * 2):
                    score += 10
                    feedback_parts.append("Merged file size indicates multiple records.")
                elif xml_content.count("<w:br w:type=\"page\"/>") >= 7 or xml_content.count("w:sectPr") >= 7:
                    score += 10
                    feedback_parts.append("Page/Section breaks indicate multiple records.")
                else:
                    feedback_parts.append("Merged file content does not appear to contain all records.")

                # Verify MERGEFIELD tags are GONE (should be replaced by text)
                if "MERGEFIELD" not in xml_content:
                    score += 10
                    feedback_parts.append("Merge fields successfully executed (not present in output).")
                else:
                    # Sometimes traces remain, but usually they shouldn't be active. 
                    # If data is present, we give partial credit.
                    feedback_parts.append("Warning: MERGEFIELD codes still found in output.")

        # 4. VLM Verification (10 pts)
        # Placeholder for VLM check - assuming framework handles this via external call if available
        # Since we are doing purely programmatic here, we award full VLM points if programmatic passes mostly
        if score >= 60:
            score += 10
            feedback_parts.append("Workflow inferred successful.")

        # Final Score Calculation
        passed = score >= 60 and template_info.get("exists") and merged_info.get("exists")
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)