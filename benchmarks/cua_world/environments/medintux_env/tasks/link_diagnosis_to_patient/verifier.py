#!/usr/bin/env python3
"""
Verifier for link_diagnosis_to_patient task in MedinTux.
"""

import json
import base64
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback/Mock for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not imported"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_diagnosis(traj, env_info, task_info):
    """
    Verify that the diagnosis I10 was linked to patient DUBOIS Marie.
    
    Scoring Criteria:
    1. Database Linkage (40 pts): Record exists in DB with 'I10' or 'Hypertension' for the patient.
    2. Output File (20 pts): Correctly formatted text file exists and is fresh.
    3. Output Content (20 pts): File contains 'DUBOIS', 'I10', 'Hypertension'.
    4. VLM Trajectory (20 pts): Visual confirmation of workflow (CIM-10 browser usage).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Database Verification (40 pts)
    db_found = result.get('db_record_found', False)
    db_record_b64 = result.get('db_record_b64', "")
    
    if db_found:
        score += 40
        feedback.append("Database: Diagnosis record found linked to patient.")
        # Optional: Decode and verify details if needed, but 'found' implies query match
    else:
        feedback.append("Database: No diagnosis record found for patient DUBOIS Marie.")

    # 2. Output File Existence & Freshness (20 pts)
    file_exists = result.get('output_file_exists', False)
    file_fresh = result.get('output_file_fresh', False)
    
    if file_exists:
        if file_fresh:
            score += 20
            feedback.append("File: Output file created during task.")
        else:
            score += 10
            feedback.append("File: Output file exists but timestamp is old.")
    else:
        feedback.append("File: Output file '/home/ga/diagnosis_result.txt' not found.")

    # 3. Output File Content (20 pts)
    content_b64 = result.get('output_content_b64', "")
    if content_b64:
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            content_lower = content.lower()
            
            c_score = 0
            if "dubois" in content_lower: c_score += 5
            if "i10" in content_lower: c_score += 10
            if "hypertension" in content_lower: c_score += 5
            
            score += c_score
            if c_score == 20:
                feedback.append("Content: File contains correct patient, code, and diagnosis.")
            elif c_score > 0:
                feedback.append(f"Content: File contains partial info ({c_score}/20 pts).")
            else:
                feedback.append("Content: File content does not match expected values.")
        except Exception:
            feedback.append("Content: Failed to decode file content.")

    # 4. VLM Verification (20 pts)
    # Only run if we don't have a perfect score yet, or to verify method
    vlm_score = 0
    if traj:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        if final_scr:
            frames.append(final_scr)
            
        if frames:
            prompt = """
            Analyze these screenshots of a medical software task (MedinTux).
            The user should be:
            1. Viewing a patient named DUBOIS Marie.
            2. Searching for or selecting a diagnosis code 'I10' (Hypertension).
            3. Linking/Saving this to the record.
            
            Do you see evidence of:
            - The patient name 'DUBOIS'?
            - A list of diagnoses or the CIM-10 browser?
            - The code 'I10' or 'Hypertension'?
            
            Return JSON: {"evidence_found": boolean, "confidence": 0-1}
            """
            
            try:
                vlm_res = query_vlm(images=frames, prompt=prompt)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('evidence_found', False):
                        vlm_score = 20
                        feedback.append("VLM: Visual evidence of diagnosis workflow found.")
                    else:
                        feedback.append("VLM: No clear visual evidence of diagnosis workflow.")
            except Exception as e:
                logger.error(f"VLM error: {e}")
    
    score += vlm_score

    # Pass logic: Must have Database record OR (File + VLM)
    # Threshold 60 matches the requirements
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }