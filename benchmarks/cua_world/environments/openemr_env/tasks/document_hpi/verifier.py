#!/usr/bin/env python3
"""
Verifier for Document HPI task in OpenEMR

Verifies that a comprehensive History of Present Illness was documented
for patient Jayson Fadel with appropriate clinical content.

Uses copy_from_env to read exported results from the container.
Includes VLM trajectory verification for anti-gaming.
"""

import sys
import os
import json
import logging
import tempfile
import re
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_document_hpi(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a comprehensive HPI was documented for the patient.
    
    Scoring (100 points total):
    - Correct patient selected: 15 points
    - Encounter created/opened: 15 points
    - HPI documentation saved: 15 points
    - Location element: 7 points
    - Quality element: 7 points
    - Severity element: 7 points
    - Duration element: 7 points
    - Context element: 7 points
    - Modifying factors element: 7 points
    - Associated symptoms element: 7 points
    - Documentation saved (verified by form count): 6 points
    
    Passing threshold: 60 points with at least 4 HPI elements documented
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    min_elements_required = metadata.get('minimum_elements_required', 4)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/document_hpi_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "encounter_opened": False,
            "hpi_documented": False,
            "location": False,
            "quality": False,
            "severity": False,
            "duration": False,
            "timing": False,
            "context": False,
            "modifying": False,
            "associated": False,
            "documentation_saved": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        counts = result.get('counts', {})
        hpi_elements = result.get('hpi_elements', {})
        new_doc_added = result.get('new_documentation_added', False)
        new_encounter_added = result.get('new_encounter_added', False)
        doc_content = result.get('documentation_content', {})
        
        logger.info(f"Result data: pid={patient_pid}, new_doc={new_doc_added}, new_encounter={new_encounter_added}")
        logger.info(f"HPI elements: {hpi_elements}")
        
        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient: expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Documentation was for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }
        
        # CRITERION 2: Encounter created/opened (15 points)
        initial_encounters = counts.get('initial_encounters', 0)
        current_encounters = counts.get('current_encounters', 0)
        initial_forms = counts.get('initial_forms', 0)
        current_forms = counts.get('current_forms', 0)
        
        if new_encounter_added or current_encounters > initial_encounters:
            score += 15
            subscores["encounter_opened"] = True
            feedback_parts.append(f"✅ Encounter created (count: {initial_encounters} -> {current_encounters})")
        elif current_forms > initial_forms:
            # Forms added to existing encounter
            score += 10
            subscores["encounter_opened"] = True
            feedback_parts.append(f"✅ Documentation added to existing encounter")
        else:
            feedback_parts.append(f"❌ No new encounter or forms detected")
        
        # CRITERION 3: HPI documentation present (15 points)
        all_text = doc_content.get('all_text', '').lower()
        elements_found = hpi_elements.get('total_count', 0)
        
        if elements_found >= 2 or (new_doc_added and len(all_text) > 50):
            score += 15
            subscores["hpi_documented"] = True
            feedback_parts.append(f"✅ HPI documentation detected with content")
        elif len(all_text) > 20:
            score += 7
            feedback_parts.append(f"⚠️ Some documentation found but limited HPI content")
        else:
            feedback_parts.append(f"❌ No HPI documentation found")
        
        # CRITERION 4-11: Individual HPI elements (7 points each)
        element_mapping = [
            ('location', 'Location (lumbar/back)'),
            ('quality', 'Quality (dull/aching/sharp)'),
            ('severity', 'Severity (6/10)'),
            ('duration', 'Duration (5 days)'),
            ('timing', 'Timing (morning/sitting)'),
            ('context', 'Context (lifting/moving)'),
            ('modifying', 'Modifying factors (rest/ibuprofen)'),
            ('associated', 'Associated symptoms (denies)')
        ]
        
        for element_key, element_name in element_mapping:
            if hpi_elements.get(element_key, False):
                score += 7
                subscores[element_key] = True
                feedback_parts.append(f"✅ {element_name}")
            else:
                feedback_parts.append(f"❌ {element_name} not found")
        
        # CRITERION 12: Documentation actually saved (6 points)
        # Verified by checking if form counts increased
        if current_forms > initial_forms or new_doc_added:
            score += 6
            subscores["documentation_saved"] = True
            feedback_parts.append(f"✅ Documentation saved to database")
        else:
            feedback_parts.append(f"❌ No new documentation saved to database")
        
        # VLM verification for trajectory (anti-gaming)
        vlm_bonus = 0
        query_vlm = env_info.get('query_vlm')
        if query_vlm and traj:
            try:
                vlm_result = verify_via_vlm(traj, query_vlm)
                if vlm_result.get('workflow_confirmed', False):
                    vlm_bonus = 5
                    feedback_parts.append(f"✅ VLM: Workflow confirmed via trajectory")
                else:
                    feedback_parts.append(f"⚠️ VLM: Could not confirm full workflow")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback_parts.append(f"⚠️ VLM verification skipped")
        
        # Add VLM bonus (capped at 100 total)
        score = min(100, score + vlm_bonus)
        
        # Determine pass/fail
        # Must have correct patient, some documentation, and at least 4 HPI elements
        key_criteria_met = (
            subscores["correct_patient"] and
            (subscores["hpi_documented"] or subscores["documentation_saved"]) and
            elements_found >= min_elements_required
        )
        
        passed = score >= 60 and key_criteria_met
        
        # Generate final feedback
        final_feedback = f"Score: {score}/100 | Elements: {elements_found}/8 | " + " | ".join(feedback_parts[:5])
        if len(feedback_parts) > 5:
            final_feedback += f" | ... and {len(feedback_parts) - 5} more criteria"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": final_feedback,
            "subscores": subscores,
            "details": {
                "elements_found": elements_found,
                "elements_required": min_elements_required,
                "new_forms_added": current_forms - initial_forms,
                "documentation_length": len(all_text)
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """
    Use VLM to verify the agent followed the correct workflow via trajectory screenshots.
    
    Checks:
    1. Agent navigated to patient chart
    2. Agent opened clinical notes/encounter form
    3. Agent typed HPI content
    4. Agent saved the documentation
    """
    # Import trajectory sampling utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        # Fallback if gym_anything not available
        logger.warning("gym_anything.vlm not available, using basic frame extraction")
        frames = traj.get('frames', [])
        if not frames:
            return {"workflow_confirmed": False, "error": "No frames available"}
        
        # Sample 5 frames across trajectory
        n_frames = min(5, len(frames))
        step = max(1, len(frames) // n_frames)
        sampled_frames = [frames[i * step] for i in range(n_frames)]
        final_frame = frames[-1] if frames else None
        
        all_frames = sampled_frames + ([final_frame] if final_frame else [])
        
        prompt = """Analyze these screenshots from an OpenEMR session to verify if the agent completed an HPI documentation task.

Look for evidence of:
1. Patient search/selection (searching for "Jayson Fadel")
2. Navigating to clinical notes or SOAP note form
3. Typing clinical content about back pain
4. Saving the documentation

The task was to document a History of Present Illness for a patient with back pain.

Respond in JSON format:
{
    "patient_search_seen": true/false,
    "clinical_form_opened": true/false,
    "text_entry_seen": true/false,
    "save_action_seen": true/false,
    "workflow_confirmed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
        
        try:
            vlm_result = query_vlm(prompt=prompt, images=all_frames)
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                return {
                    "workflow_confirmed": parsed.get('workflow_confirmed', False),
                    "confidence": parsed.get('confidence', 'low'),
                    "details": parsed
                }
        except Exception as e:
            logger.warning(f"VLM query failed: {e}")
        
        return {"workflow_confirmed": False, "error": "VLM query failed"}
    
    # Use proper trajectory sampling
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        all_frames = frames + ([final] if final else [])
        
        if not all_frames:
            return {"workflow_confirmed": False, "error": "No frames available"}
        
        prompt = """Analyze these screenshots from an OpenEMR electronic health record session.

The task was to document a History of Present Illness (HPI) for patient Jayson Fadel who has back pain.

Look for evidence that the agent:
1. Searched for and selected patient Jayson Fadel
2. Opened a clinical notes form, SOAP note, or encounter
3. Typed clinical documentation about back pain (HPI content)
4. Saved the documentation

Respond in JSON format:
{
    "patient_search_seen": true/false,
    "clinical_form_opened": true/false,
    "text_entry_seen": true/false,
    "save_action_seen": true/false,
    "workflow_confirmed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observed"
}
"""
        
        vlm_result = query_vlm(prompt=prompt, images=all_frames)
        
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            return {
                "workflow_confirmed": parsed.get('workflow_confirmed', False),
                "confidence": parsed.get('confidence', 'low'),
                "details": parsed
            }
        else:
            return {
                "workflow_confirmed": False,
                "error": vlm_result.get('error', 'Unknown VLM error')
            }
            
    except Exception as e:
        logger.warning(f"VLM trajectory verification failed: {e}")
        return {"workflow_confirmed": False, "error": str(e)}


# For testing/debugging
if __name__ == "__main__":
    # Test with mock data
    mock_result = {
        "patient_pid": 3,
        "task_start_timestamp": 1700000000,
        "task_end_timestamp": 1700000300,
        "counts": {
            "initial_forms": 5,
            "current_forms": 7,
            "initial_encounters": 2,
            "current_encounters": 3,
            "initial_soap": 1,
            "current_soap": 2,
            "initial_clinical": 0,
            "current_clinical": 0
        },
        "new_documentation_added": True,
        "new_encounter_added": True,
        "hpi_elements": {
            "location": True,
            "quality": True,
            "severity": True,
            "duration": True,
            "timing": False,
            "context": True,
            "modifying": True,
            "associated": False,
            "total_count": 6
        },
        "documentation_content": {
            "soap_note": "Patient presents with lower back pain in lumbar region...",
            "clinical_note": "",
            "encounter_reason": "Back pain",
            "all_text": "lower back pain lumbar dull aching 6/10 5 days lifting boxes rest ibuprofen"
        }
    }
    
    print("Mock verification test:")
    print(json.dumps(mock_result, indent=2))