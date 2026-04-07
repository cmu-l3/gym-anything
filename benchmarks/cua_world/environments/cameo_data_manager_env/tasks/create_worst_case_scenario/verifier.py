#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import PyPDF2
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_worst_case_scenario(traj, env_info, task_info):
    """
    Verifies that the agent created the Worst Case Scenario in CAMEO Data Manager.
    
    Verification Logic:
    1. Checks if the agent generated the PDF report (hard evidence).
    2. Parses the PDF to verify specific data values (1.5 m/s wind, 14.0 miles, etc.).
    3. Uses VLM on the trajectory to confirm the workflow was performed in the UI.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {}).get('parameters', {})
    
    # Define scoring
    score = 0
    feedback_log = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Result JSON & Artifacts
    # ------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    
    try:
        # Get JSON
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Get PDF if it exists
        pdf_downloaded = False
        if result_data.get('output_exists'):
            try:
                copy_from_env("C:\\Users\\Docker\\Documents\\scenario_report.pdf", temp_pdf.name)
                pdf_downloaded = True
            except Exception as e:
                feedback_log.append(f"Failed to copy output PDF: {str(e)}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Setup failed: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ------------------------------------------------------------------
    # 2. Evaluate PDF Content (Primary Evidence) - Max 50 pts
    # ------------------------------------------------------------------
    pdf_score = 0
    if pdf_downloaded and result_data.get('file_created_during_task'):
        try:
            with open(temp_pdf.name, 'rb') as f:
                reader = PyPDF2.PdfReader(f)
                text = ""
                for page in reader.pages:
                    text += page.extract_text() + "\n"
                
                text = text.lower()
                
                # Check Key Values
                checks = [
                    (metadata.get('facility', '').lower(), 5, "Facility Name"),
                    (metadata.get('chemical', '').lower(), 5, "Chemical Name"),
                    ("worst case", 10, "Scenario Type"),
                    ("1.5", 5, "Wind Speed (1.5)"),
                    ("180,000", 5, "Release Quantity"),
                    ("10", 5, "Duration"),
                    ("14.0", 15, "Endpoint Distance (14.0 mi)")
                ]
                
                for term, pts, label in checks:
                    # Loose matching for numbers to handle formatting
                    if term in text:
                        pdf_score += pts
                        feedback_log.append(f"✓ Found {label}")
                    elif term.replace(',', '') in text: # Handle 180000 vs 180,000
                        pdf_score += pts
                        feedback_log.append(f"✓ Found {label}")
                    else:
                        feedback_log.append(f"✗ Missing {label} in report")
                        
        except Exception as e:
            feedback_log.append(f"Error reading PDF: {str(e)}")
    else:
        feedback_log.append("No report file created during task.")

    score += pdf_score

    # ------------------------------------------------------------------
    # 3. VLM Trajectory Verification - Max 50 pts
    # ------------------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    prompt = f"""
    Analyze these screenshots from CAMEO Data Manager.
    Goal: Create a 'Worst Case' scenario for Chlorine.
    
    Look for:
    1. Navigation to the "Scenarios" section.
    2. Data entry of "1.5" for wind speed or "F" for stability.
    3. "14.0 miles" being entered or displayed as the endpoint distance.
    4. A final save action or report generation dialog.
    
    Did the agent perform these steps?
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    vlm_score = 0
    if "yes" in vlm_result.get('response', '').lower() or "performed" in vlm_result.get('response', '').lower():
        vlm_score = 50
        feedback_log.append("✓ VLM confirmed workflow.")
    else:
        # Partial credit based on confidence
        vlm_score = 25
        feedback_log.append("? VLM partial confirmation.")
        
    score += vlm_score

    # Cleanup PDF
    if os.path.exists(temp_pdf.name):
        os.unlink(temp_pdf.name)

    passed = (score >= 70) and (pdf_score >= 20)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }