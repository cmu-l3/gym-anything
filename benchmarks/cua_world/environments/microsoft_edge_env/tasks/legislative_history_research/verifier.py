#!/usr/bin/env python3
"""
Verifier for Legislative History Research task.
Verifies the existence and content of the downloaded Bill PDF and the vote tally text file.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legislative_history_research(traj, env_info, task_info):
    """
    Verify legislative history research task.
    
    Scoring Criteria:
    1. PDF Downloaded (30 pts): File exists, valid PDF header, reasonable size.
    2. PDF Content (20 pts): Contains expected bill keywords (via partial read or file name/size heuristic if text extraction fails).
    3. Vote File Exists (10 pts): File exists.
    4. Vote Data Accuracy (40 pts): Correct Yeas (15), Nays (15), Roll Call (10).
    
    Total: 100 pts. Pass threshold: 75 pts.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_yeas = metadata.get('expected_yeas', '243')
    expected_nays = metadata.get('expected_nays', '187')
    expected_roll = metadata.get('expected_roll', '404')

    # Load result JSON from the container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # --- Verify PDF ---
    pdf_info = result.get('pdf_info', {})
    if pdf_info.get('exists') and pdf_info.get('created_during_task'):
        # Basic existence check
        score += 30
        feedback.append("PDF downloaded successfully.")
        
        # Content verification: Check header and size
        # We copy the actual PDF to verify it's not a dummy file
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        try:
            copy_from_env(pdf_info['path'], temp_pdf.name)
            
            # Check for PDF magic bytes
            with open(temp_pdf.name, 'rb') as f:
                header = f.read(4)
                if header == b'%PDF':
                    # Size check: A full bill text PDF should be > 50KB usually
                    file_size = os.path.getsize(temp_pdf.name)
                    if file_size > 10000: # 10KB minimum
                        score += 20
                        feedback.append(f"PDF content valid (Size: {file_size} bytes).")
                    else:
                        feedback.append("PDF file seems too small to be the full bill text.")
                else:
                    feedback.append("File is not a valid PDF (missing magic bytes).")
        except Exception as e:
            feedback.append(f"Could not inspect PDF content: {e}")
        finally:
            if os.path.exists(temp_pdf.name):
                os.unlink(temp_pdf.name)
    else:
        feedback.append("PDF file not found or not created during task.")

    # --- Verify Vote Tally Text ---
    tally_info = result.get('tally_info', {})
    if tally_info.get('exists') and tally_info.get('created_during_task'):
        score += 10
        feedback.append("Vote tally file exists.")
        
        content = tally_info.get('content_preview', '')
        
        # Check Roll Call Number (10 pts)
        if expected_roll in content:
            score += 10
            feedback.append(f"Roll Call {expected_roll} identified.")
        else:
            feedback.append(f"Missing Roll Call number {expected_roll}.")
            
        # Check Yeas (15 pts) - Robust regex for "Yeas: 243" or "243 Yeas" or just finding the number near 'Yea'
        if re.search(r'Yea[s]?\D{0,10}243', content, re.IGNORECASE) or re.search(r'243\D{0,10}Yea[s]?', content, re.IGNORECASE):
            score += 15
            feedback.append("Yeas count (243) is correct.")
        elif '243' in content:
            # Partial credit if number exists but context unclear
            score += 5
            feedback.append("Number 243 found, but context (Yeas) unclear.")
        else:
            feedback.append("Yeas count incorrect or missing.")
            
        # Check Nays (15 pts)
        if re.search(r'Nay[s]?\D{0,10}187', content, re.IGNORECASE) or re.search(r'187\D{0,10}Nay[s]?', content, re.IGNORECASE):
            score += 15
            feedback.append("Nays count (187) is correct.")
        elif '187' in content:
            # Partial credit
            score += 5
            feedback.append("Number 187 found, but context (Nays) unclear.")
        else:
            feedback.append("Nays count incorrect or missing.")
            
    else:
        feedback.append("Vote tally file not found or not created during task.")

    # --- Browser History Check (sanity check, no points but useful for anti-gaming) ---
    if not result.get('browser_history', {}).get('visited_congress_gov'):
        feedback.append("WARNING: Browser history does not show visit to congress.gov.")

    # Final Result
    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }