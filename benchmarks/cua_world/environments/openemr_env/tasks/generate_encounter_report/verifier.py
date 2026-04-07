#!/usr/bin/env python3
"""
Verifier for Generate Encounter Report PDF task in OpenEMR

Verification Strategy:
1. PRIMARY: Check that a valid PDF file was created during the task
2. SECONDARY: Verify PDF content contains patient/encounter information
3. TERTIARY: Use VLM to verify workflow progression through trajectory

Scoring (100 points):
- PDF file exists: 25 points
- Valid PDF format: 15 points
- Created during task (anti-gaming): 15 points
- Reasonable file size (>1KB): 10 points
- Contains patient information: 15 points
- Contains encounter data: 10 points
- VLM workflow verification: 10 points

Pass threshold: 65 points with PDF existing and valid format
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_generate_encounter_report(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that an encounter report PDF was correctly generated.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available for verification"
        }
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/encounter_report.pdf')
    patient_fname = metadata.get('patient_fname', 'Jayson')
    patient_lname = metadata.get('patient_lname', 'Fadel')
    scoring = metadata.get('scoring', {})
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "pdf_exists": False,
        "valid_format": False,
        "created_during_task": False,
        "reasonable_size": False,
        "contains_patient": False,
        "contains_encounter": False,
        "vlm_verified": False
    }
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/encounter_report_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        logger.info(f"Result data: {json.dumps(result, indent=2)}")
        
        # Extract verification data
        pdf_exists = result.get('pdf_exists', False)
        pdf_path = result.get('pdf_actual_path', '')
        pdf_size = result.get('pdf_size_bytes', 0)
        pdf_mtime = result.get('pdf_mtime', 0)
        task_start = result.get('task_start_time', 0)
        pdf_valid = result.get('pdf_valid_format', False)
        pdf_created_during_task = result.get('pdf_created_during_task', False)
        pdf_contains_patient = result.get('pdf_contains_patient_name', False)
        pdf_contains_encounter = result.get('pdf_contains_encounter_data', False)
        
        # CRITERION 1: PDF file exists (25 points)
        points_exists = scoring.get('pdf_exists', 25)
        if pdf_exists:
            score += points_exists
            subscores["pdf_exists"] = True
            if pdf_path == expected_path:
                feedback_parts.append(f"✅ PDF found at expected location: {pdf_path}")
            else:
                feedback_parts.append(f"✅ PDF found at: {pdf_path} (not exact expected path)")
        else:
            feedback_parts.append("❌ No PDF file found")
            # Early return if no PDF - can't verify further
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: Valid PDF format (15 points)
        points_valid = scoring.get('valid_pdf_format', 15)
        if pdf_valid:
            score += points_valid
            subscores["valid_format"] = True
            feedback_parts.append("✅ Valid PDF format confirmed")
        else:
            feedback_parts.append("❌ File is not a valid PDF format")
        
        # CRITERION 3: Created during task - CRITICAL for anti-gaming (15 points)
        points_created = scoring.get('created_during_task', 15)
        if pdf_created_during_task:
            score += points_created
            subscores["created_during_task"] = True
            feedback_parts.append("✅ PDF was created during task execution")
        else:
            feedback_parts.append("❌ PDF was NOT created during task (possible pre-existing file)")
            # This is a significant red flag - don't give full credit
        
        # CRITERION 4: Reasonable file size (10 points)
        points_size = scoring.get('reasonable_size', 10)
        min_size = 1000  # 1KB minimum
        if pdf_size >= min_size:
            score += points_size
            subscores["reasonable_size"] = True
            feedback_parts.append(f"✅ PDF has reasonable size: {pdf_size} bytes")
        else:
            feedback_parts.append(f"❌ PDF too small ({pdf_size} bytes) - may be empty or corrupted")
        
        # CRITERION 5: Contains patient information (15 points)
        points_patient = scoring.get('contains_patient_info', 15)
        if pdf_contains_patient:
            score += points_patient
            subscores["contains_patient"] = True
            feedback_parts.append(f"✅ PDF contains patient name ({patient_fname} {patient_lname})")
        else:
            # Try to verify from extracted text
            text_verified = verify_pdf_text_content(copy_from_env, patient_fname, patient_lname)
            if text_verified.get('patient_found', False):
                score += points_patient
                subscores["contains_patient"] = True
                feedback_parts.append(f"✅ Patient name verified in PDF content")
            else:
                feedback_parts.append("❌ Patient name not found in PDF content")
        
        # CRITERION 6: Contains encounter/medical data (10 points)
        points_encounter = scoring.get('contains_encounter_data', 10)
        if pdf_contains_encounter:
            score += points_encounter
            subscores["contains_encounter"] = True
            feedback_parts.append("✅ PDF contains medical/encounter content")
        else:
            feedback_parts.append("⚠️ Medical content not clearly identified in PDF")
        
        # CRITERION 7: VLM workflow verification (10 points)
        points_vlm = scoring.get('vlm_workflow_verified', 10)
        vlm_result = verify_workflow_via_vlm(traj, env_info, patient_fname, patient_lname)
        if vlm_result.get('workflow_verified', False):
            score += points_vlm
            subscores["vlm_verified"] = True
            feedback_parts.append("✅ VLM confirmed correct workflow execution")
        else:
            vlm_feedback = vlm_result.get('feedback', 'VLM verification unavailable')
            feedback_parts.append(f"⚠️ {vlm_feedback}")
        
        # Determine pass/fail
        # Must have: PDF exists + valid format + created during task
        key_criteria_met = (
            subscores["pdf_exists"] and 
            subscores["valid_format"] and 
            subscores["created_during_task"]
        )
        
        passed = score >= 65 and key_criteria_met
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "pdf_path": pdf_path,
                "pdf_size": pdf_size,
                "expected_path": expected_path
            }
        }
        
    except FileNotFoundError as e:
        logger.error(f"Result file not found: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verification data not found - export may have failed",
            "subscores": subscores
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse verification data: {e}",
            "subscores": subscores
        }
    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": subscores
        }


def verify_pdf_text_content(copy_from_env, patient_fname: str, patient_lname: str) -> Dict[str, Any]:
    """
    Verify PDF content by checking extracted text.
    
    Args:
        copy_from_env: Function to copy files from container
        patient_fname: Expected patient first name
        patient_lname: Expected patient last name
        
    Returns:
        Dict with verification results
    """
    result = {
        "patient_found": False,
        "encounter_content": False,
        "text_available": False
    }
    
    try:
        # Try to get extracted text
        temp_text = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/pdf_extracted_text.txt", temp_text.name)
            with open(temp_text.name, 'r', errors='ignore') as f:
                text = f.read().lower()
            result["text_available"] = True
            
            # Check for patient name
            if patient_fname.lower() in text or patient_lname.lower() in text:
                result["patient_found"] = True
            
            # Check for encounter/medical keywords
            medical_keywords = ['encounter', 'visit', 'diagnosis', 'patient', 'provider', 
                              'assessment', 'medical', 'clinical', 'date', 'chief complaint']
            if any(kw in text for kw in medical_keywords):
                result["encounter_content"] = True
                
        finally:
            if os.path.exists(temp_text.name):
                os.unlink(temp_text.name)
                
    except Exception as e:
        logger.warning(f"Could not verify PDF text content: {e}")
    
    return result


def verify_workflow_via_vlm(traj: Dict[str, Any], env_info: Dict[str, Any], 
                           patient_fname: str, patient_lname: str) -> Dict[str, Any]:
    """
    Use VLM to verify the agent followed correct workflow.
    
    Checks trajectory frames (not just final screenshot) to verify:
    1. Agent navigated to patient search/selection
    2. Agent opened patient chart
    3. Agent accessed encounter or report generation
    4. Agent saved/downloaded a file
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with query_vlm function
        patient_fname: Patient first name
        patient_lname: Patient last name
        
    Returns:
        Dict with workflow verification results
    """
    result = {
        "workflow_verified": False,
        "feedback": "VLM verification not performed"
    }
    
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        result["feedback"] = "VLM query function not available"
        return result
    
    try:
        # Import trajectory utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory (not just final screenshot!)
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        
        if not frames and not final_frame:
            result["feedback"] = "No trajectory frames available"
            return result
        
        # Combine frames for analysis
        all_frames = frames + ([final_frame] if final_frame else [])
        
        # VLM prompt to verify workflow
        vlm_prompt = f"""You are verifying if a computer agent completed a medical record task correctly.

TASK: Generate a PDF report of a clinical encounter for patient {patient_fname} {patient_lname}.

The agent should have:
1. Logged into OpenEMR (medical records system)
2. Searched for and selected the patient {patient_fname} {patient_lname}
3. Opened the patient's chart or encounter list
4. Generated or printed a report/PDF of an encounter
5. Saved the report file

Looking at these screenshots from the agent's session, determine:
1. Does this show OpenEMR or a medical records interface?
2. Did the agent navigate to a patient record?
3. Is there evidence of report generation, printing, or PDF creation?
4. Did the agent appear to complete the file save workflow?

Respond in JSON format:
{{
    "is_medical_system": true/false,
    "patient_record_accessed": true/false,
    "report_generation_attempted": true/false,
    "file_save_observed": true/false,
    "workflow_complete": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}}
"""
        
        vlm_response = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        
        if not vlm_response.get("success"):
            result["feedback"] = f"VLM query failed: {vlm_response.get('error', 'Unknown error')}"
            return result
        
        parsed = vlm_response.get("parsed", {})
        
        # Evaluate workflow completion
        is_medical = parsed.get("is_medical_system", False)
        patient_accessed = parsed.get("patient_record_accessed", False)
        report_attempted = parsed.get("report_generation_attempted", False)
        workflow_complete = parsed.get("workflow_complete", False)
        confidence = parsed.get("confidence", "low")
        reasoning = parsed.get("reasoning", "")
        
        # Workflow is verified if key steps were observed
        if workflow_complete and confidence in ["medium", "high"]:
            result["workflow_verified"] = True
            result["feedback"] = f"Workflow verified: {reasoning}"
        elif is_medical and patient_accessed and report_attempted:
            result["workflow_verified"] = True
            result["feedback"] = "Key workflow steps observed"
        else:
            result["feedback"] = f"Incomplete workflow: {reasoning}"
        
        result["vlm_details"] = parsed
        
    except ImportError:
        result["feedback"] = "VLM utilities not available"
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        result["feedback"] = f"VLM verification error: {str(e)}"
    
    return result


# Additional helper for manual testing
if __name__ == "__main__":
    # Test with mock data
    mock_result = {
        "pdf_exists": True,
        "pdf_actual_path": "/home/ga/Documents/encounter_report.pdf",
        "pdf_size_bytes": 15000,
        "pdf_mtime": 1700000000,
        "task_start_time": 1699999900,
        "pdf_valid_format": True,
        "pdf_created_during_task": True,
        "pdf_contains_patient_name": True,
        "pdf_contains_encounter_data": True
    }
    print("Mock verification would check:", json.dumps(mock_result, indent=2))