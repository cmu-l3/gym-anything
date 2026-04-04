#!/usr/bin/env python3
"""
Verifier for contract_redline_generation task.

Verification Strategy:
1. Check if output file exists and was created during task.
2. Analyze DOCX XML structure for Tracked Changes tags (<w:ins>, <w:del>).
   - This proves the agent used the "Compare/Track Changes" feature rather than manual editing.
3. Verify specific content changes are tracked:
   - Payment: 30 -> 60
   - Liability: 1,000,000 -> 500,000
   - Termination: 15 -> 90
4. VLM Verification: Check trajectory frames to confirm UI interaction.
"""

import json
import os
import zipfile
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_contract_redline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Output file exists (10 pts)
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'supply_agreement_redline.docx' not found."}
    
    score += 10
    feedback_parts.append("Output file exists")

    # Criterion 2: Created during task (10 pts)
    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates it was NOT created during task")

    # Get the docx file for content analysis
    temp_docx = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    try:
        copy_from_env("/home/ga/Documents/supply_agreement_redline.docx", temp_docx.name)
        
        # Analyze XML for tracked changes tags
        # We need to look into word/document.xml inside the zip
        try:
            with zipfile.ZipFile(temp_docx.name, 'r') as docx_zip:
                xml_content = docx_zip.read('word/document.xml').decode('utf-8')
            
            # Criterion 3: Tracked Changes Tags Present (30 pts)
            # Look for <w:ins> (insertions) and <w:del> (deletions)
            # Simple regex check for presence
            has_ins = bool(re.search(r'<w:ins\b', xml_content))
            has_del = bool(re.search(r'<w:del\b', xml_content))
            
            if has_ins and has_del:
                score += 30
                feedback_parts.append("Tracked changes metadata found")
            else:
                feedback_parts.append("FAIL: No tracked changes tags found (did you use Compare Document?)")
            
            # Criterion 4: Content Specific Checks (30 pts)
            # We look for the specific values being modified.
            # XML is messy, e.g. <w:del ...><w:t>30</w:t></w:del> ... <w:ins ...><w:t>60</w:t></w:ins>
            
            # Payment: 30 -> 60
            payment_change = False
            if re.search(r'<w:del[^>]*>.*?30.*?</w:del>', xml_content, re.DOTALL) and \
               re.search(r'<w:ins[^>]*>.*?60.*?</w:ins>', xml_content, re.DOTALL):
                payment_change = True
            
            # Liability: 1,000,000 -> 500,000
            liability_change = False
            if re.search(r'<w:del[^>]*>.*?1,000,000.*?</w:del>', xml_content, re.DOTALL) and \
               re.search(r'<w:ins[^>]*>.*?500,000.*?</w:ins>', xml_content, re.DOTALL):
                liability_change = True
                
            # Termination: 15 -> 90
            term_change = False
            if re.search(r'<w:del[^>]*>.*?15.*?</w:del>', xml_content, re.DOTALL) and \
               re.search(r'<w:ins[^>]*>.*?90.*?</w:ins>', xml_content, re.DOTALL):
                term_change = True
                
            detected_changes = sum([payment_change, liability_change, term_change])
            score += detected_changes * 10
            
            if detected_changes == 3:
                feedback_parts.append("All 3 critical changes detected correctly")
            else:
                feedback_parts.append(f"Only {detected_changes}/3 specific changes detected")

        except zipfile.BadZipFile:
            feedback_parts.append("Output file is not a valid DOCX/ZIP")
            
    except Exception as e:
        feedback_parts.append(f"Error analyzing document: {str(e)}")
    finally:
        if os.path.exists(temp_docx.name):
            os.unlink(temp_docx.name)

    # Criterion 5: VLM Verification (20 pts)
    # Check if UI shows comparison view or red markings
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    images_to_check = frames + ([final_screen] if final_screen else [])
    
    vlm_score = 0
    if images_to_check:
        prompt = """
        Analyze these screenshots of LibreOffice Writer.
        Do you see any of the following:
        1. "Redline" markup text (crossed out text, underlined colored text)?
        2. A "Compare" or "Track Changes" toolbar active?
        3. A dialog box for "Compare to" or "Merge Document"?
        
        Return JSON: {"evidence_found": true/false, "description": "what you see"}
        """
        
        # We query just the last few frames to save tokens, or just sample one good one
        result = query_vlm(images=images_to_check, prompt=prompt)
        if result.get("success") and result.get("parsed", {}).get("evidence_found"):
            vlm_score = 20
            feedback_parts.append("Visual evidence of redlining found")
        else:
            feedback_parts.append("No visual evidence of redlining process")
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }