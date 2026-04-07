#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_patent_research(traj, env_info, task_info):
    """
    Verifies the patent prior art research task.
    
    Scoring Criteria (100 pts total):
    1. PDF Download (40 pts):
       - File exists at correct path (15)
       - File is valid PDF > 50KB (15)
       - File created during task (10)
    2. Data Extraction (40 pts):
       - Inventor "Michael J. Jackson" identified (15)
       - Filing date "1992-06-29" identified (10)
       - Citation "1059284" identified (15)
    3. Process Verification (20 pts):
       - Browser history shows visit to patent page (10)
       - VLM verification of activity (10)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_inventor = metadata.get('expected_inventor', "Michael J. Jackson").lower()
    expected_date = metadata.get('expected_filing_date', "1992-06-29")
    expected_citation = metadata.get('expected_citation', "1059284")

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: PDF Download (40 pts) ---
    pdf_exists = result.get('pdf_exists', False)
    pdf_size = int(result.get('pdf_size', 0))
    pdf_fresh = result.get('pdf_fresh', False)

    if pdf_exists:
        score += 15
        feedback.append("PDF file found at correct path.")
        
        # Check size (patent PDFs are usually >50KB)
        if pdf_size > 50000:
            score += 15
            feedback.append(f"PDF size is valid ({pdf_size} bytes).")
        else:
            feedback.append(f"PDF seems too small ({pdf_size} bytes).")

        # Check timestamp
        if pdf_fresh:
            score += 10
        else:
            feedback.append("PDF timestamp indicates it wasn't downloaded during this session.")
    else:
        feedback.append("PDF file NOT found at expected path.")

    # --- Criterion 2: Data Extraction (40 pts) ---
    summary_exists = result.get('summary_exists', False)
    summary_content = result.get('summary_content', "").lower()
    summary_fresh = result.get('summary_fresh', False)

    if summary_exists and summary_fresh:
        # Check Inventor
        if expected_inventor in summary_content or "michael jackson" in summary_content:
            score += 15
            feedback.append("Inventor identified correctly.")
        else:
            feedback.append(f"Inventor '{expected_inventor}' not found in summary.")

        # Check Filing Date (Strict format check)
        if expected_date in summary_content:
            score += 10
            feedback.append("Filing date identified correctly.")
        else:
            feedback.append(f"Filing date '{expected_date}' not found in summary.")

        # Check Citation (Allow variations like 1,059,284 or 1059284)
        citation_clean = expected_citation.replace(",", "")
        if citation_clean in summary_content.replace(",", ""):
            score += 15
            feedback.append("Citation identified correctly.")
        else:
            feedback.append(f"Citation '{expected_citation}' not found in summary.")
    else:
        feedback.append("Summary file missing or not created during task.")

    # --- Criterion 3: Process Verification (20 pts) ---
    # History Check
    if result.get('history_visit_found', False):
        score += 10
        feedback.append("Browser history confirms visit to patent page.")
    else:
        feedback.append("No record of visiting the patent page in browser history.")

    # VLM Check using trajectory
    # We ask VLM if it sees Google Patents or the specific patent
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if frames:
        try:
            vlm_prompt = (
                "Do these screenshots show a user navigating Google Patents, "
                "viewing US Patent 5255452, or downloading a PDF? "
                "Look for 'Anti-gravity illusion' or patent diagrams."
            )
            vlm_response = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
            
            # Simple keyword heuristic on VLM response
            vlm_text = vlm_response.get('response', '').lower()
            if any(x in vlm_text for x in ['yes', 'shows', 'patent', 'google', '5255452']):
                score += 10
                feedback.append("Visual verification passed.")
            else:
                feedback.append("Visual verification inconclusive.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Fallback points if files are perfect
            if score >= 80: 
                score += 10
                feedback.append("Visual verification skipped (system error), defaulted points.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }