#!/usr/bin/env python3
"""
Verifier for Document Physical Exam task in OpenEMR

Verification Strategy:
1. Check if a clinical form (SOAP, clinical notes) was created/modified
2. Verify correct patient association (pid=3)
3. Check for required body system documentation
4. Verify specific clinical terminology is present
5. Confirm form was created DURING the task (anti-gaming)

Scoring (100 points total):
- Form created: 20 points
- Correct patient: 15 points
- Encounter linked: 15 points
- General/HEENT documented: 15 points
- Cardiovascular documented: 10 points
- Respiratory documented: 10 points
- Abdomen documented: 10 points
- Timestamp valid: 5 points
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_physical_exam(traj, env_info, task_info):
    """
    Verify that physical exam findings were properly documented.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    required_systems = metadata.get('required_systems', 
        ['general', 'heent', 'neck', 'cardiovascular', 'respiratory', 'abdomen'])
    scoring_weights = metadata.get('scoring_weights', {})
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/physical_exam_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "form_created": False,
            "correct_patient": False,
            "encounter_linked": False,
            "general_heent": False,
            "cardiovascular": False,
            "respiratory": False,
            "abdomen": False,
            "timestamp_valid": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        encounter_id = result.get('encounter_id', 0)
        task_start = result.get('task_start', 0)
        task_end = result.get('task_end', 0)
        initial_forms = result.get('initial_form_count', 0)
        current_forms = result.get('current_form_count', 0)
        initial_soap = result.get('initial_soap_count', 0)
        current_soap = result.get('current_soap_count', 0)
        new_form_created = result.get('new_form_created', False)
        systems = result.get('systems_documented', {})
        soap_content = result.get('soap_objective_content', '')
        clinical_content = result.get('clinical_note_content', '')
        
        logger.info(f"Result: pid={patient_pid}, encounter={encounter_id}, new_form={new_form_created}")
        logger.info(f"Systems documented: {systems}")
        
        # CRITERION 1: Form was created (20 points)
        form_created = (current_forms > initial_forms or current_soap > initial_soap or new_form_created)
        has_content = bool(soap_content.strip() or clinical_content.strip())
        
        if form_created or has_content:
            score += 20
            subscores["form_created"] = True
            if current_soap > initial_soap:
                feedback_parts.append(f"✅ SOAP note created (count: {initial_soap} → {current_soap})")
            elif current_forms > initial_forms:
                feedback_parts.append(f"✅ Clinical form created (count: {initial_forms} → {current_forms})")
            else:
                feedback_parts.append("✅ Clinical documentation found")
        else:
            feedback_parts.append("❌ No new clinical form/note detected")
        
        # CRITERION 2: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"❌ Wrong patient (expected pid={expected_pid}, got {patient_pid})")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Documentation for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }
        
        # CRITERION 3: Encounter linked (15 points)
        if encounter_id and encounter_id > 0:
            score += 15
            subscores["encounter_linked"] = True
            feedback_parts.append(f"✅ Linked to encounter #{encounter_id}")
        else:
            feedback_parts.append("❌ No encounter linkage detected")
        
        # CRITERION 4: General/HEENT documented (15 points)
        has_general = systems.get('general', False)
        has_heent = systems.get('heent', False)
        
        if has_general and has_heent:
            score += 15
            subscores["general_heent"] = True
            feedback_parts.append("✅ General and HEENT examination documented")
        elif has_general or has_heent:
            score += 8  # Partial credit
            documented = []
            if has_general:
                documented.append("General")
            if has_heent:
                documented.append("HEENT")
            feedback_parts.append(f"⚠️ Partial: {', '.join(documented)} documented")
        else:
            feedback_parts.append("❌ General/HEENT examination not documented")
        
        # CRITERION 5: Cardiovascular documented (10 points)
        if systems.get('cardiovascular', False):
            score += 10
            subscores["cardiovascular"] = True
            feedback_parts.append("✅ Cardiovascular examination documented")
        else:
            feedback_parts.append("❌ Cardiovascular examination not documented")
        
        # CRITERION 6: Respiratory documented (10 points)
        if systems.get('respiratory', False):
            score += 10
            subscores["respiratory"] = True
            feedback_parts.append("✅ Respiratory examination documented")
        else:
            feedback_parts.append("❌ Respiratory examination not documented")
        
        # CRITERION 7: Abdomen documented (10 points)
        if systems.get('abdomen', False):
            score += 10
            subscores["abdomen"] = True
            feedback_parts.append("✅ Abdominal examination documented")
        else:
            feedback_parts.append("❌ Abdominal examination not documented")
        
        # CRITERION 8: Timestamp validity (5 points) - anti-gaming
        if task_end > task_start and (task_end - task_start) > 10:
            # Task took at least 10 seconds (reasonable for documentation)
            score += 5
            subscores["timestamp_valid"] = True
            duration = task_end - task_start
            feedback_parts.append(f"✅ Task completed in {duration}s")
        else:
            feedback_parts.append("⚠️ Task duration suspiciously short")
        
        # Calculate total systems documented
        total_systems = systems.get('total_count', 0)
        feedback_parts.append(f"\nBody systems documented: {total_systems}/6")
        
        # Determine pass/fail
        # Must have: form created + correct patient + at least 3 body systems
        key_criteria_met = (
            subscores["form_created"] and 
            subscores["correct_patient"] and 
            total_systems >= 3
        )
        
        passed = score >= 60 and key_criteria_met
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "systems_documented": systems,
                "total_systems": total_systems,
                "content_length": len(soap_content) + len(clinical_content)
            }
        }
        
    except FileNotFoundError as e:
        logger.error(f"Result file not found: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed"
        }
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid result format: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_with_vlm(traj, env_info, task_info):
    """
    Optional VLM-based verification to supplement database checks.
    Uses trajectory frames to verify actual documentation workflow.
    """
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Get trajectory frames (not just final screenshot)
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"vlm_verified": False, "reason": "No screenshots available"}
        
        query_vlm_func = env_info.get('query_vlm')
        if not query_vlm_func:
            return {"vlm_verified": False, "reason": "VLM function not available"}
        
        # Analyze trajectory to verify workflow
        prompt = """Analyze these screenshots from an OpenEMR medical records system session.

TASK: Document physical examination findings for a patient.

Look at the sequence of screenshots and determine:
1. Did the user access a patient chart (patient name visible)?
2. Did they open a clinical documentation form (SOAP note, clinical notes, or exam form)?
3. Is there evidence of text being entered about physical examination findings?
4. Look for medical terms like: General, HEENT, Cardiovascular, Respiratory, Abdomen

Respond in JSON:
{
    "patient_chart_accessed": true/false,
    "clinical_form_opened": true/false,
    "exam_documentation_visible": true/false,
    "medical_terms_seen": ["list", "of", "terms"],
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
        
        all_images = frames + ([final] if final else [])
        vlm_result = query_vlm_func(prompt=prompt, images=all_images)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            return {
                "vlm_verified": True,
                "patient_chart_accessed": parsed.get("patient_chart_accessed", False),
                "clinical_form_opened": parsed.get("clinical_form_opened", False),
                "exam_documentation_visible": parsed.get("exam_documentation_visible", False),
                "medical_terms_seen": parsed.get("medical_terms_seen", []),
                "confidence": parsed.get("confidence", "low")
            }
        else:
            return {"vlm_verified": False, "reason": vlm_result.get("error", "VLM query failed")}
            
    except ImportError:
        return {"vlm_verified": False, "reason": "VLM module not available"}
    except Exception as e:
        return {"vlm_verified": False, "reason": str(e)}


if __name__ == "__main__":
    # Test verification with mock data
    mock_result = {
        "patient_pid": 3,
        "encounter_id": 1,
        "task_start": 1000,
        "task_end": 1120,
        "initial_form_count": 5,
        "current_form_count": 6,
        "initial_soap_count": 2,
        "current_soap_count": 3,
        "new_form_created": True,
        "systems_documented": {
            "general": True,
            "heent": True,
            "neck": True,
            "cardiovascular": True,
            "respiratory": True,
            "abdomen": True,
            "total_count": 6
        },
        "soap_objective_content": "General: Alert, oriented x3. HEENT: Normocephalic, PERRLA. Cardiovascular: RRR. Respiratory: Clear to auscultation. Abdomen: Soft, non-tender.",
        "clinical_note_content": ""
    }
    
    print("Mock verification result:")
    print(json.dumps(mock_result, indent=2))