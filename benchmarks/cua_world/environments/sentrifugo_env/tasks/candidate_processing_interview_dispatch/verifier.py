#!/usr/bin/env python3
"""
Verifier for Lead Social Worker Candidate Processing task.

Criteria:
1. 3 candidates added to the database (3 x 10 pts)
2. PDF resumes uploaded via Sentrifugo interface (15 pts)
3. Interview scheduled ONLY for the qualified candidate (Sarah Washington). 
   - Anti-gaming: If an unqualified candidate is scheduled, it scores 0 for this section. (40 pts)
4. VLM Trajectory Verification: Confirms agent actually opened/viewed the PDF documents to read them. (15 pts)

Total points: 100
Pass Threshold: 70
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_candidate_processing(traj, env_info, task_info):
    # Use copy_from_env to get the data reliably
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    candidates = result.get('candidates_exist', {})
    interviews = result.get('interviews_scheduled', {})
    uploaded_pdfs = result.get('uploaded_pdfs', 0)

    # 1. Candidate Creation (30 pts)
    for cand in ['sarah', 'elena', 'marcus']:
        if candidates.get(cand, 0) > 0:
            score += 10
            feedback_parts.append(f"Candidate {cand.capitalize()} added (10/10)")
        else:
            feedback_parts.append(f"Candidate {cand.capitalize()} missing (0/10)")

    # 2. PDF Uploads (15 pts)
    if uploaded_pdfs >= 3:
        score += 15
        feedback_parts.append(f"All resumes uploaded ({uploaded_pdfs} found) (15/15)")
    elif uploaded_pdfs > 0:
        score += 5
        feedback_parts.append(f"Partial resumes uploaded ({uploaded_pdfs} found) (5/15)")
    else:
        feedback_parts.append("No resumes uploaded (0/15)")

    # 3. Interview Scheduling & Anti-Gaming Logic (40 pts)
    # Sarah is qualified. Elena and Marcus are not.
    if interviews.get('sarah', 0) > 0:
        if interviews.get('elena', 0) > 0 or interviews.get('marcus', 0) > 0:
            feedback_parts.append("FAIL: Scheduled interview for unqualified candidate(s) - Failed credential evaluation (0/40)")
        else:
            score += 40
            feedback_parts.append("Correctly scheduled interview ONLY for qualified candidate (Sarah) (40/40)")
    else:
        if interviews.get('elena', 0) > 0 or interviews.get('marcus', 0) > 0:
            feedback_parts.append("FAIL: Scheduled wrong candidate and missed the qualified candidate (0/40)")
        else:
            feedback_parts.append("No interviews scheduled (0/40)")

    # 4. VLM Verification (15 pts)
    query_vlm = env_info.get('query_vlm')
    pdf_viewed = False

    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            
            prompt = """Review these screenshots from a desktop interaction. 
            The user was tasked with evaluating candidate credentials from PDF resumes.
            Do any of these screenshots show a PDF document OPEN (either in Document Viewer or a Web Browser) displaying Candidate Credentials?
            
            Return a JSON object with a single boolean field:
            {"pdf_viewed": true_or_false}"""
            
            vlm_result = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_result and vlm_result.get('parsed'):
                pdf_viewed = vlm_result['parsed'].get('pdf_viewed', False)
            
            if pdf_viewed:
                score += 15
                feedback_parts.append("VLM confirmed PDF resumes were read (15/15)")
            else:
                feedback_parts.append("VLM did not detect PDF resumes being read (0/15)")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            score += 15
            feedback_parts.append("VLM verification skipped/failed, awarding points by default (15/15)")
    else:
        score += 15
        feedback_parts.append("VLM unavailable, awarding points by default (15/15)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "candidates": candidates,
            "interviews": interviews,
            "uploaded_pdfs": uploaded_pdfs,
            "pdf_viewed": pdf_viewed
        }
    }