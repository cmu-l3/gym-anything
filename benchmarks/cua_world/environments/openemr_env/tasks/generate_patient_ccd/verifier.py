#!/usr/bin/env python3
"""
Verifier for Generate Patient CCD Task in OpenEMR

Verifies that a Continuity of Care Document (CCD/CCDA) was generated
for the specified patient. Uses copy_from_env to read exported results
and optionally uses VLM to verify workflow progression.

Scoring (100 points total):
- Patient was selected correctly: 15 points
- CCD interface was accessed (based on workflow): 20 points
- File was generated during task: 30 points
- Valid CCD format (contains ClinicalDocument): 15 points
- Contains correct patient data: 15 points
- Contains clinical content sections: 5 points
"""

import sys
import os
import json
import logging
import tempfile
import re
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_generate_ccd(traj, env_info, task_info):
    """
    Verify that a CCD document was generated for the correct patient.
    
    Args:
        traj: Trajectory data with frames and episode information
        env_info: Environment info including copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Rickie')
    expected_lname = metadata.get('patient_lname', 'Batz')
    expected_dob = metadata.get('patient_dob', '1990-08-14')
    ccd_markers = metadata.get('ccd_markers', ['ClinicalDocument', 'recordTarget', 'component'])
    scoring_weights = metadata.get('scoring_weights', {})
    
    score = 0
    feedback_parts = []
    subscores = {
        "patient_selected": False,
        "ccd_interface_accessed": False,
        "file_generated": False,
        "valid_ccd_format": False,
        "correct_patient_data": False,
        "clinical_content_present": False
    }
    
    # =========================================================================
    # Step 1: Read exported result JSON
    # =========================================================================
    result = None
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/generate_ccd_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read export result: {str(e)}"
        }
    
    if not result:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No result data exported"
        }
    
    logger.info(f"Export result: {json.dumps(result, indent=2)}")
    
    # =========================================================================
    # Step 2: Check if CCD file was generated
    # =========================================================================
    ccd_found = result.get('ccd_file_found', False)
    ccd_path = result.get('ccd_file_path', '')
    ccd_size = result.get('ccd_file_size_bytes', 0)
    valid_format = result.get('valid_ccd_format', False)
    has_patient_data = result.get('contains_patient_data', False)
    has_clinical = result.get('contains_clinical_content', False)
    
    # Anti-gaming: Check task duration (task should take some time)
    task_duration = result.get('task_duration_seconds', 0)
    if task_duration < 10:
        feedback_parts.append(f"WARNING: Task completed very quickly ({task_duration}s) - may be gaming")
    
    # =========================================================================
    # Criterion 1: File was generated (30 points)
    # =========================================================================
    if ccd_found and ccd_size > 0:
        score += 30
        subscores["file_generated"] = True
        feedback_parts.append(f"✅ CCD file generated: {ccd_path} ({ccd_size} bytes)")
    else:
        feedback_parts.append("❌ No CCD file was generated during the task")
        
        # Check Firefox title for hints
        firefox_title = result.get('firefox_title', '')
        if firefox_title and ('ccd' in firefox_title.lower() or 'clinical' in firefox_title.lower()):
            feedback_parts.append(f"Note: Firefox title suggests CCD may have been viewed: '{firefox_title}'")
            # Give partial credit for getting to CCD interface
            score += 10
    
    # =========================================================================
    # Criterion 2: Valid CCD format (15 points)
    # =========================================================================
    if valid_format:
        score += 15
        subscores["valid_ccd_format"] = True
        feedback_parts.append("✅ File contains valid CCD/CCDA format (ClinicalDocument marker)")
    elif ccd_found:
        feedback_parts.append("❌ File found but does not appear to be valid CCD format")
    
    # =========================================================================
    # Criterion 3: Contains correct patient data (15 points)
    # =========================================================================
    if has_patient_data:
        score += 15
        subscores["correct_patient_data"] = True
        feedback_parts.append(f"✅ CCD contains patient data for {expected_fname} {expected_lname}")
    elif ccd_found:
        feedback_parts.append(f"❌ CCD does not contain expected patient identifiers ({expected_fname} {expected_lname})")
    
    # =========================================================================
    # Criterion 4: Contains clinical content (5 points)
    # =========================================================================
    if has_clinical:
        score += 5
        subscores["clinical_content_present"] = True
        feedback_parts.append("✅ CCD contains clinical content sections")
    elif ccd_found:
        feedback_parts.append("⚠️ CCD may not contain clinical content sections")
    
    # =========================================================================
    # Step 3: Try to read and analyze actual CCD content (if available)
    # =========================================================================
    ccd_content = None
    try:
        temp_ccd = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env("/tmp/generated_ccd.xml", temp_ccd.name)
            with open(temp_ccd.name, 'r', errors='ignore') as f:
                ccd_content = f.read()
        finally:
            if os.path.exists(temp_ccd.name):
                os.unlink(temp_ccd.name)
    except Exception as e:
        logger.debug(f"Could not read CCD content: {e}")
    
    # Additional validation on actual content
    if ccd_content:
        logger.info(f"CCD content length: {len(ccd_content)}")
        
        # Double-check patient data in actual content
        if not subscores["correct_patient_data"]:
            if expected_fname.lower() in ccd_content.lower() and expected_lname.lower() in ccd_content.lower():
                score += 15
                subscores["correct_patient_data"] = True
                feedback_parts.append(f"✅ Verified patient data in CCD content: {expected_fname} {expected_lname}")
        
        # Check for DOB
        if expected_dob in ccd_content:
            feedback_parts.append(f"✅ Patient DOB ({expected_dob}) found in CCD")
        
        # Check for standard CCD sections
        sections_found = []
        section_patterns = [
            (r'templateId.*2\.16\.840\.1\.113883\.10\.20\.22\.2\.5', 'Problems'),
            (r'templateId.*2\.16\.840\.1\.113883\.10\.20\.22\.2\.1', 'Medications'),
            (r'templateId.*2\.16\.840\.1\.113883\.10\.20\.22\.2\.6', 'Allergies'),
            (r'<component>', 'Components'),
            (r'<recordTarget>', 'RecordTarget'),
        ]
        
        for pattern, section_name in section_patterns:
            if re.search(pattern, ccd_content, re.IGNORECASE):
                sections_found.append(section_name)
        
        if sections_found:
            feedback_parts.append(f"CCD sections found: {', '.join(sections_found)}")
    
    # =========================================================================
    # Step 4: VLM Verification for workflow (patient selection, CCD interface)
    # =========================================================================
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Import VLM utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames from trajectory to verify workflow
            frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if frames or final_screenshot:
                all_images = (frames or []) + ([final_screenshot] if final_screenshot else [])
                
                vlm_prompt = f"""You are verifying if an agent completed a CCD (Continuity of Care Document) export task in OpenEMR.

TASK: Generate a CCD document for patient {expected_fname} {expected_lname} (DOB: {expected_dob})

Examine these screenshots from the task trajectory and determine:
1. Was the patient {expected_fname} {expected_lname} selected/visible in the patient header?
2. Did the agent navigate to a CCD, Reports, or Export interface?
3. Is there evidence of a CCD being generated or displayed (XML content, download, clinical document)?

Respond in JSON format:
{{
    "patient_selected": true/false,
    "ccd_interface_accessed": true/false,
    "ccd_generated_or_displayed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_images)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    # Criterion: Patient selected (15 points)
                    if parsed.get('patient_selected', False):
                        if not subscores["patient_selected"]:
                            score += 15
                            subscores["patient_selected"] = True
                            feedback_parts.append(f"✅ VLM confirms patient {expected_fname} {expected_lname} was selected")
                    
                    # Criterion: CCD interface accessed (20 points)
                    if parsed.get('ccd_interface_accessed', False):
                        if not subscores["ccd_interface_accessed"]:
                            score += 20
                            subscores["ccd_interface_accessed"] = True
                            feedback_parts.append("✅ VLM confirms CCD/export interface was accessed")
                    
                    # Additional evidence of CCD generation
                    if parsed.get('ccd_generated_or_displayed', False):
                        feedback_parts.append("✅ VLM confirms CCD was generated or displayed")
                    
                    reasoning = parsed.get('reasoning', '')
                    if reasoning:
                        feedback_parts.append(f"VLM analysis: {reasoning}")
                        
        except ImportError:
            logger.debug("VLM utilities not available")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
    
    # =========================================================================
    # Step 5: Determine pass/fail
    # =========================================================================
    
    # Key criteria for passing:
    # - Must have generated a file OR accessed the CCD interface
    # - Score must be >= 50
    
    key_criteria_met = (
        subscores["file_generated"] or 
        (subscores["ccd_interface_accessed"] and subscores["patient_selected"])
    )
    
    passed = score >= 50 and key_criteria_met
    
    # Bonus for complete success
    if all(subscores.values()):
        feedback_parts.append("🎉 All criteria met - excellent work!")
    
    # Cap score at 100
    score = min(score, 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "ccd_file_path": ccd_path,
            "ccd_file_size": ccd_size,
            "task_duration_seconds": task_duration,
            "expected_patient": f"{expected_fname} {expected_lname} (pid={expected_pid})"
        }
    }