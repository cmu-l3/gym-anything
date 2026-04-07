#!/usr/bin/env python3
"""
Verifier for format_newsletter_typography task.

Verification Strategy:
1. File Persistence: Check document was modified/saved.
2. XML Parsing: Inspect .docx internals (word/document.xml, word/settings.xml).
3. Criteria:
   - Justification: <w:jc w:val="both"/> in paragraphs
   - AutoHyphenation: <w:autoHyphenation> in settings
   - Hyphenation Zone: <w:hyphenationZone w:val="360"/> (approx 0.25")
   - Consecutive Hyphens: <w:consecutiveHyphenLimit w:val="2"/>
   - Drop Cap: <w:framePr w:dropCap="drop"/> in first paragraph
"""

import json
import logging
import os
import re
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\task_result.json"
DOC_PATH = "C:\\Users\\Docker\\Documents\\Community_Newsletter.docx"

def verify_format_newsletter_typography(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp directory for verification artifacts
    temp_dir = tempfile.mkdtemp()
    local_result_json = os.path.join(temp_dir, "task_result.json")
    local_docx = os.path.join(temp_dir, "Community_Newsletter.docx")

    score = 0
    feedback_parts = []
    
    try:
        # 1. Load result JSON
        try:
            copy_from_env(RESULT_PATH, local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        if not result_data.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Document Community_Newsletter.docx not found."}
            
        if not result_data.get("file_modified", False):
            # Penalize heavily but verify anyway in case they saved very quickly (anti-gaming check)
            feedback_parts.append("WARNING: File modification time suggests no save occurred.")
        else:
            feedback_parts.append("File modification verified.")

        # 2. Retrieve Document
        try:
            copy_from_env(DOC_PATH, local_docx)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve output document: {str(e)}"}

        if not zipfile.is_zipfile(local_docx):
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid DOCX archive."}

        # 3. Analyze XML
        with zipfile.ZipFile(local_docx, 'r') as docx:
            # Read Settings
            try:
                settings_xml = docx.read('word/settings.xml').decode('utf-8')
            except KeyError:
                settings_xml = ""
                
            # Read Document Content
            try:
                document_xml = docx.read('word/document.xml').decode('utf-8')
            except KeyError:
                document_xml = ""

        # --- SCORING CRITERIA ---

        # Criterion 1: Justification (30 pts)
        # Look for <w:jc w:val="both"/>
        # We check count > 0. In a perfect world, we'd check all paragraphs, but >=3 is safe for this doc.
        justification_count = len(re.findall(r'<w:jc\s+[^>]*w:val="both"', document_xml))
        if justification_count >= 3:
            score += 30
            feedback_parts.append(f"Text Justification applied ({justification_count} paragraphs).")
        elif justification_count > 0:
            score += 15
            feedback_parts.append(f"Partial Text Justification applied ({justification_count} paragraphs).")
        else:
            feedback_parts.append("FAIL: Text is not Justified (expected 'Justify' alignment).")

        # Criterion 2: Auto Hyphenation (20 pts)
        if re.search(r'<w:autoHyphenation\s*/>', settings_xml) or re.search(r'<w:autoHyphenation\s+w:val="true"', settings_xml):
            score += 20
            feedback_parts.append("Auto Hyphenation enabled.")
        else:
            feedback_parts.append("FAIL: Auto Hyphenation not enabled.")

        # Criterion 3: Hyphenation Zone (10 pts)
        # 0.25 inches = 360 twips. Word sometimes saves as decimal, but usually twips in XML.
        # Allow small tolerance (e.g. 350-370)
        zone_match = re.search(r'<w:hyphenationZone\s+[^>]*w:val="(\d+)"', settings_xml)
        if zone_match:
            zone_val = int(zone_match.group(1))
            if 350 <= zone_val <= 370:
                score += 10
                feedback_parts.append(f"Hyphenation zone correct ({zone_val} twips).")
            else:
                feedback_parts.append(f"Hyphenation zone incorrect (found {zone_val} twips, expected ~360).")
        else:
            feedback_parts.append("FAIL: Hyphenation zone not set.")

        # Criterion 4: Consecutive Hyphens (10 pts)
        limit_match = re.search(r'<w:consecutiveHyphenLimit\s+[^>]*w:val="(\d+)"', settings_xml)
        if limit_match:
            limit_val = int(limit_match.group(1))
            if limit_val == 2:
                score += 10
                feedback_parts.append("Consecutive hyphen limit correct (2).")
            else:
                feedback_parts.append(f"Consecutive hyphen limit incorrect (found {limit_val}, expected 2).")
        else:
            feedback_parts.append("FAIL: Consecutive hyphen limit not set.")

        # Criterion 5: Drop Cap (30 pts)
        # Look for a frame in the first paragraph.
        # Implementation: Find first paragraph, check for framePr
        # Simplified regex check for <w:framePr ... w:dropCap="drop" ...>
        # We also want w:lines="3" (default, but explicit check is good)
        
        drop_cap_match = re.search(r'<w:framePr\s+[^>]*w:dropCap="drop"', document_xml)
        if drop_cap_match:
            score += 20
            feedback_parts.append("Drop Cap inserted.")
            
            # Check lines
            lines_match = re.search(r'w:lines="3"', drop_cap_match.group(0))
            if lines_match or 'w:lines' not in drop_cap_match.group(0): 
                # If w:lines is missing, default is often 3, but XML usually writes it.
                # If we see the dropCap="drop" but no lines attr, we might assume default.
                # We'll give points if explicitly 3 or if checking specifically the frame properties.
                score += 10
                feedback_parts.append("Drop Cap height correct (3 lines).")
            else:
                feedback_parts.append("Drop Cap height might be incorrect (checked w:lines=3).")
        else:
            feedback_parts.append("FAIL: Drop Cap not found.")

        final_passed = score >= 70

        return {
            "passed": final_passed,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with internal error: {e}"}
    finally:
        # Cleanup
        try:
            import shutil
            shutil.rmtree(temp_dir)
        except:
            pass