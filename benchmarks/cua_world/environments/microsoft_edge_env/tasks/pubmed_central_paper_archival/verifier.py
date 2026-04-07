#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pubmed_archival(traj, env_info, task_info):
    """
    Verifies the PubMed Central Paper Archival task.
    
    Criteria:
    1. Directory ~/Documents/JournalClub exists (10 pts)
    2. At least 3 PDF files exist in that directory (30 pts)
    3. Files are named correctly (FirstAuthor_Year.pdf) (30 pts)
    4. Files are valid PDFs and created during task (15 pts)
    5. VLM verification of PubMed usage (15 pts)
    """
    
    # 1. Setup and load data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Check Directory (10 pts)
    if data.get("directory_exists"):
        score += 10
        feedback.append("Directory 'JournalClub' created.")
    else:
        feedback.append("FAIL: Directory ~/Documents/JournalClub not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 3. Analyze Files
    files = data.get("files", [])
    valid_pdfs = []
    
    # Filter for valid files (created during task, actual PDF content)
    for f in files:
        if f.get("is_pdf_content") and f.get("created_after_start"):
            valid_pdfs.append(f)
    
    # Score Count (30 pts)
    if len(valid_pdfs) >= 3:
        score += 30
        feedback.append(f"Found {len(valid_pdfs)} valid PDF files (>=3).")
    elif len(valid_pdfs) > 0:
        partial = len(valid_pdfs) * 10
        score += partial
        feedback.append(f"Found only {len(valid_pdfs)} valid PDF files (expected 3).")
    else:
        feedback.append("FAIL: No valid PDF files found created during the task.")
    
    # Score Naming Convention (30 pts)
    # Pattern: Author_Year.pdf (e.g. Smith_2023.pdf)
    pattern = re.compile(r"^[A-Za-z]+_\d{4}\.pdf$")
    correctly_named = 0
    
    for f in valid_pdfs:
        if pattern.match(f["name"]):
            correctly_named += 1
            
    if correctly_named >= 3:
        score += 30
        feedback.append("All files follow the 'Author_Year.pdf' naming convention.")
    elif correctly_named > 0:
        partial = correctly_named * 10
        score += partial
        feedback.append(f"Only {correctly_named} files follow the naming convention.")
    else:
        if len(valid_pdfs) > 0:
            feedback.append(f"Naming convention check failed. Example found: {valid_pdfs[0]['name']}")
        else:
            feedback.append("Naming convention check failed (no files).")

    # Score File Validity/Creation (15 pts)
    # Already filtered valid_pdfs by content and timestamp, so if we have them, we give points
    if len(valid_pdfs) >= 3:
        score += 15
    elif len(valid_pdfs) > 0:
        score += 5 * len(valid_pdfs)

    # 4. VLM Verification (15 pts)
    # Check if agent actually used PubMed
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "Does the user appear to be searching for scientific papers on PubMed or PubMed Central? "
            "Look for 'PubMed', 'NIH', 'NCBI', or lists of medical articles. "
            "Answer 'YES' or 'NO' and explain briefly."
        )
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if "YES" in vlm_result.get("response", "").upper():
            score += 15
            feedback.append("Visual verification passed: PubMed usage detected.")
        else:
            feedback.append("Visual verification warning: PubMed usage not clearly visible in trajectory.")
            # Fallback to history check if VLM fails/is unsure
            if data.get("history_found"):
                score += 15
                feedback.append("Fallback verification: Browser history confirms PubMed access.")
            else:
                feedback.append("FAIL: No visual or history evidence of visiting PubMed.")
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # Fallback to history
        if data.get("history_found"):
            score += 15
            feedback.append("VLM failed, but browser history confirms PubMed access.")

    # Final check
    passed = score >= 70 and len(valid_pdfs) >= 2 # Pass if decent attempt made
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }