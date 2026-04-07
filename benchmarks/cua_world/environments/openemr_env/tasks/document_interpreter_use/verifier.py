#!/usr/bin/env python3
"""
Verifier for Document Interpreter Use Task in OpenEMR

Verifies that interpreter service use was properly documented during a patient encounter.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- Login/access successful (implied by documentation): 5 points
- Correct patient accessed: 10 points
- Encounter accessed/created: 15 points
- Language (Spanish) documented: 15 points
- Interpreter type (telephone) documented: 15 points
- Service provider (CyraCom) documented: 15 points
- Duration (25 min) documented: 10 points
- Appropriate note content: 10 points
- Documentation saved: 5 points

Pass threshold: 65 points with key criteria met (patient, language, interpreter type)
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_interpreter_documentation(traj, env_info, task_info):
    """
    Verify that interpreter service documentation was correctly added to the patient's record.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info including copy_from_env function
        task_info: Task info with metadata including expected values
        
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
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Maria')
    expected_lname = metadata.get('patient_lname', 'Santos')
    expected_language = metadata.get('interpreter_language', 'Spanish').lower()
    expected_type = metadata.get('interpreter_type', 'telephone').lower()
    expected_provider = metadata.get('interpreter_provider', 'CyraCom').lower()
    expected_duration = metadata.get('interpreter_duration', 25)
    
    # Scoring weights
    weights = metadata.get('scoring_weights', {
        'login_successful': 5,
        'correct_patient': 10,
        'encounter_accessed': 15,
        'language_documented': 15,
        'interpreter_type_documented': 15,
        'provider_documented': 15,
        'duration_documented': 10,
        'note_content': 10,
        'documentation_saved': 5
    })
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/interpreter_use_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
                
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read verification data: {str(e)}"
        }
    
    score = 0
    feedback_parts = []
    subscores = {
        "login_successful": False,
        "correct_patient": False,
        "encounter_accessed": False,
        "language_documented": False,
        "interpreter_type_documented": False,
        "provider_documented": False,
        "duration_documented": False,
        "note_content_appropriate": False,
        "documentation_saved": False
    }
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    initial_notes = result.get('initial_notes_count', 0)
    current_notes = result.get('current_notes_count', 0)
    initial_forms = result.get('initial_forms_count', 0)
    current_forms = result.get('current_forms_count', 0)
    new_notes_added = result.get('new_notes_added', False)
    new_forms_added = result.get('new_forms_added', False)
    doc_checks = result.get('documentation_checks', {})
    note_content = result.get('note_content_sample', '').lower()
    task_start = result.get('task_start_timestamp', 0)
    task_end = result.get('task_end_timestamp', 0)
    
    logger.info(f"Result data: pid={patient_pid}, notes={initial_notes}->{current_notes}, forms={initial_forms}->{current_forms}")
    logger.info(f"Documentation checks: {doc_checks}")
    
    # CRITERION 1: Login successful (inferred from any documentation being found)
    # If documentation was added, user must have logged in
    interpreter_found = doc_checks.get('interpreter_doc_found', False)
    if interpreter_found or new_notes_added or new_forms_added:
        score += weights['login_successful']
        subscores['login_successful'] = True
        feedback_parts.append("✓ Login successful (documentation accessed)")
    else:
        feedback_parts.append("✗ No evidence of successful login/documentation")
    
    # CRITERION 2: Correct patient (10 points)
    if patient_pid == expected_pid:
        score += weights['correct_patient']
        subscores['correct_patient'] = True
        feedback_parts.append(f"✓ Correct patient accessed (pid={expected_pid})")
    else:
        feedback_parts.append(f"✗ Wrong patient (expected pid={expected_pid}, got {patient_pid})")
    
    # CRITERION 3: Encounter accessed (15 points)
    # Evidence: new notes or forms added, or documentation found
    if new_notes_added or new_forms_added or interpreter_found:
        score += weights['encounter_accessed']
        subscores['encounter_accessed'] = True
        feedback_parts.append("✓ Encounter documentation accessed")
    else:
        feedback_parts.append("✗ No encounter documentation found")
    
    # CRITERION 4: Language documented (15 points)
    language_found = doc_checks.get('language_documented', False)
    # Also check note content directly
    if not language_found and expected_language in note_content:
        language_found = True
    if language_found:
        score += weights['language_documented']
        subscores['language_documented'] = True
        feedback_parts.append("✓ Language (Spanish) documented")
    else:
        feedback_parts.append("✗ Language not documented")
    
    # CRITERION 5: Interpreter type documented (15 points)
    type_found = doc_checks.get('interpreter_type_documented', False)
    # Also check note content for variations
    type_keywords = ['telephone', 'phone', 'telephonic']
    if not type_found:
        for keyword in type_keywords:
            if keyword in note_content:
                type_found = True
                break
    if type_found:
        score += weights['interpreter_type_documented']
        subscores['interpreter_type_documented'] = True
        feedback_parts.append("✓ Interpreter type (telephone) documented")
    else:
        feedback_parts.append("✗ Interpreter type not documented")
    
    # CRITERION 6: Service provider documented (15 points)
    provider_found = doc_checks.get('provider_documented', False)
    # Also check for partial matches
    if not provider_found and (expected_provider in note_content or 'sp-44721' in note_content):
        provider_found = True
    if provider_found:
        score += weights['provider_documented']
        subscores['provider_documented'] = True
        feedback_parts.append("✓ Service provider (CyraCom) documented")
    else:
        feedback_parts.append("✗ Service provider not documented")
    
    # CRITERION 7: Duration documented (10 points)
    duration_found = doc_checks.get('duration_documented', False)
    # Check for duration in note content
    duration_patterns = [
        r'25\s*(min|minute)',
        r'twenty.?five',
        r'duration.*25',
        r'25.*duration'
    ]
    if not duration_found:
        for pattern in duration_patterns:
            if re.search(pattern, note_content):
                duration_found = True
                break
    if duration_found:
        score += weights['duration_documented']
        subscores['duration_documented'] = True
        feedback_parts.append("✓ Duration (25 min) documented")
    else:
        feedback_parts.append("✗ Duration not documented")
    
    # CRITERION 8: Appropriate note content (10 points)
    # Check for contextual keywords indicating proper documentation
    content_keywords = ['interpreter', 'diabetes', 'follow', 'education', 'visit', 'patient']
    keywords_found = sum(1 for kw in content_keywords if kw in note_content)
    if keywords_found >= 3:
        score += weights['note_content']
        subscores['note_content_appropriate'] = True
        feedback_parts.append(f"✓ Note content appropriate ({keywords_found} relevant keywords)")
    elif keywords_found > 0:
        partial_score = int(weights['note_content'] * keywords_found / 3)
        score += partial_score
        feedback_parts.append(f"◐ Partial note content ({keywords_found}/3 keywords, +{partial_score} pts)")
    else:
        feedback_parts.append("✗ Note content missing relevant context")
    
    # CRITERION 9: Documentation saved (5 points)
    # Evidence: new notes/forms count increased OR interpreter doc found
    if new_notes_added or new_forms_added:
        score += weights['documentation_saved']
        subscores['documentation_saved'] = True
        notes_added = current_notes - initial_notes
        forms_added = current_forms - initial_forms
        feedback_parts.append(f"✓ Documentation saved ({notes_added} notes, {forms_added} forms added)")
    elif interpreter_found:
        # Partial credit if documentation found but counts didn't change
        # (might be due to timing or different storage location)
        score += int(weights['documentation_saved'] * 0.5)
        feedback_parts.append("◐ Documentation found (partial credit)")
    else:
        feedback_parts.append("✗ No documentation saved")
    
    # Anti-gaming: Check timestamp validity
    if task_end > 0 and task_start > 0:
        task_duration = task_end - task_start
        if task_duration < 10:
            # Suspiciously fast - might be gaming
            logger.warning(f"Task completed very quickly: {task_duration}s")
            feedback_parts.append(f"⚠ Task completed in {task_duration}s (unusually fast)")
    
    # Calculate pass/fail
    # Key criteria: correct patient, language, interpreter type
    key_criteria_met = (
        subscores['correct_patient'] and
        (subscores['language_documented'] or subscores['interpreter_type_documented'])
    )
    
    passed = score >= 65 and key_criteria_met
    
    # VLM verification for additional context (if available)
    query_vlm = env_info.get('query_vlm')
    if query_vlm and not passed:
        # Try VLM as fallback verification
        try:
            from gym_anything.vlm import get_final_screenshot
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_prompt = """Look at this OpenEMR screenshot. 
                Is there evidence of interpreter service documentation being added?
                Look for:
                1. Clinical notes or encounter documentation visible
                2. Any text mentioning "interpreter", "Spanish", "telephone", or "CyraCom"
                3. A patient chart or encounter form open
                
                Respond with JSON: {"interpreter_doc_visible": true/false, "confidence": "low/medium/high", "evidence": "brief description"}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, image=final_screenshot)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('interpreter_doc_visible') and parsed.get('confidence') in ['medium', 'high']:
                        score += 10
                        feedback_parts.append(f"✓ VLM confirmed interpreter documentation visible (+10 pts)")
                        if score >= 65:
                            passed = True
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": subscores,
        "details": {
            "patient_pid": patient_pid,
            "notes_added": current_notes - initial_notes,
            "forms_added": current_forms - initial_forms,
            "documentation_checks": doc_checks,
            "note_content_preview": note_content[:200] if note_content else ""
        }
    }