#!/usr/bin/env python3
"""
Verifier for Document Patient Education task in OpenEMR

Verifies that patient education was properly documented for a diabetic patient.
Uses copy_from_env to read exported verification data and VLM for trajectory analysis.

Scoring (100 points total):
- Correct patient selected (25 pts)
- New documentation created (20 pts)
- Encounter context established (15 pts)
- Education content documented (25 pts)
- Content quality/keywords (15 pts)
"""

import sys
import os
import json
import logging
import tempfile
import re
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Education-related keywords to look for
EDUCATION_KEYWORDS = [
    'diet', 'diabetes', 'diabetic', 'nutrition', 'carbohydrate', 'glucose',
    'education', 'counseling', 'counselled', 'taught', 'instruction',
    'glycemic', 'meal', 'food', 'eating', 'blood sugar', 'handout',
    'aha', 'ada', 'guidelines', 'patient education'
]


def check_education_keywords(text: str) -> Dict[str, Any]:
    """
    Check if text contains education-related keywords.
    
    Args:
        text: Text content to analyze
        
    Returns:
        Dict with keyword analysis results
    """
    if not text:
        return {"found": False, "keywords_found": [], "keyword_count": 0}
    
    text_lower = text.lower()
    keywords_found = []
    
    for keyword in EDUCATION_KEYWORDS:
        if keyword.lower() in text_lower:
            keywords_found.append(keyword)
    
    # Check for diabetes + diet combination (more specific)
    has_diabetes_mention = any(k in text_lower for k in ['diabetes', 'diabetic', 'dm', 'type 2'])
    has_diet_mention = any(k in text_lower for k in ['diet', 'nutrition', 'carbohydrate', 'meal', 'food', 'eating'])
    has_education_mention = any(k in text_lower for k in ['education', 'counseling', 'counselled', 'taught', 'instruction'])
    
    return {
        "found": len(keywords_found) > 0,
        "keywords_found": keywords_found,
        "keyword_count": len(keywords_found),
        "has_diabetes_mention": has_diabetes_mention,
        "has_diet_mention": has_diet_mention,
        "has_education_mention": has_education_mention,
        "is_relevant_education": has_diabetes_mention and (has_diet_mention or has_education_mention)
    }


def verify_patient_education(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that patient education was documented correctly.
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info including copy_from_env function
        task_info: Task info including metadata
        
    Returns:
        Dict with passed, score, feedback, and details
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
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Jacinto')
    expected_lname = metadata.get('patient_lname', 'Kiehn')
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "correct_patient": False,
        "newly_created": False,
        "encounter_context": False,
        "education_documented": False,
        "content_quality": False
    }
    details = {}
    
    # Copy result JSON from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/patient_education_result.json", temp_result.name)
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
            "feedback": f"Could not read verification data: {e}"
        }
    
    details['exported_result'] = result
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    patient_name = result.get('patient_name', '')
    initial_counts = result.get('initial_counts', {})
    current_counts = result.get('current_counts', {})
    new_doc_exists = result.get('new_documentation_exists', False)
    encounter_created = result.get('encounter_created', False)
    education_found = result.get('education_documentation_found', False)
    doc_type = result.get('documentation_type', '')
    doc_content = result.get('documentation_content', '')
    newest_pnote_content = result.get('newest_pnote_content', '')
    newest_encounter_reason = result.get('newest_encounter_reason', '')
    
    logger.info(f"Verifying education documentation for patient pid={patient_pid}")
    logger.info(f"New documentation exists: {new_doc_exists}, Education found: {education_found}")
    
    # CRITERION 1: Correct patient (25 points)
    if patient_pid == expected_pid:
        score += 25
        subscores["correct_patient"] = True
        feedback_parts.append(f"✅ Correct patient selected: {expected_fname} {expected_lname} (pid={expected_pid})")
    else:
        feedback_parts.append(f"❌ Wrong patient! Expected pid={expected_pid}, got pid={patient_pid}")
        # Critical failure - return early with low score
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": details
        }
    
    # CRITERION 2: New documentation created (20 points)
    forms_added = current_counts.get('forms', 0) - initial_counts.get('forms', 0)
    pnotes_added = current_counts.get('pnotes', 0) - initial_counts.get('pnotes', 0)
    
    if new_doc_exists or forms_added > 0 or pnotes_added > 0:
        score += 20
        subscores["newly_created"] = True
        feedback_parts.append(f"✅ New documentation created (forms: +{forms_added}, notes: +{pnotes_added})")
    else:
        feedback_parts.append("❌ No new documentation was created during task")
        # This is a significant failure but not complete - continue scoring
    
    # CRITERION 3: Encounter context established (15 points)
    encounters_added = current_counts.get('encounters', 0) - initial_counts.get('encounters', 0)
    
    if encounter_created or encounters_added > 0:
        score += 15
        subscores["encounter_context"] = True
        feedback_parts.append(f"✅ Encounter context established (+{encounters_added} encounters)")
    elif new_doc_exists:
        # Partial credit if documentation exists even without explicit new encounter
        # (might have used existing encounter)
        score += 8
        feedback_parts.append("⚠️ Documentation added but no new encounter detected (may have used existing)")
    else:
        feedback_parts.append("❌ No encounter context established")
    
    # CRITERION 4: Education content documented (25 points)
    # Analyze all available content for education keywords
    all_content = f"{doc_content} {newest_pnote_content} {newest_encounter_reason}"
    keyword_analysis = check_education_keywords(all_content)
    
    details['keyword_analysis'] = keyword_analysis
    
    if education_found and keyword_analysis['is_relevant_education']:
        score += 25
        subscores["education_documented"] = True
        feedback_parts.append(f"✅ Diabetic diet education documented ({keyword_analysis['keyword_count']} keywords found)")
    elif education_found or keyword_analysis['found']:
        # Partial credit for some education-related content
        partial_score = 15 if keyword_analysis['keyword_count'] >= 2 else 10
        score += partial_score
        subscores["education_documented"] = True
        feedback_parts.append(f"⚠️ Education content found but may not be specific to diabetic diet ({keyword_analysis['keyword_count']} keywords)")
    elif new_doc_exists:
        # Some credit for creating documentation even without keywords
        score += 5
        feedback_parts.append("⚠️ Documentation created but education keywords not detected")
    else:
        feedback_parts.append("❌ No education content documented")
    
    # CRITERION 5: Content quality (15 points)
    if keyword_analysis['is_relevant_education']:
        # Full points for relevant diabetes diet education
        if keyword_analysis['keyword_count'] >= 4:
            score += 15
            subscores["content_quality"] = True
            feedback_parts.append(f"✅ High quality content with {keyword_analysis['keyword_count']} relevant keywords")
        elif keyword_analysis['keyword_count'] >= 2:
            score += 10
            subscores["content_quality"] = True
            feedback_parts.append(f"✅ Good content quality ({keyword_analysis['keyword_count']} keywords)")
        else:
            score += 5
            feedback_parts.append("⚠️ Basic content quality")
    elif keyword_analysis['has_diabetes_mention'] or keyword_analysis['has_diet_mention']:
        score += 5
        feedback_parts.append("⚠️ Partial content - mentions diabetes or diet but not both")
    else:
        feedback_parts.append("❌ Content does not mention diabetic diet education")
    
    # VLM verification using trajectory frames
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample trajectory frames to verify workflow
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                vlm_prompt = """Analyze these screenshots from an OpenEMR (Electronic Health Records) task.

The task was to document patient education about diabetic diet for patient Jacinto Kiehn.

Please determine:
1. Was the patient Jacinto Kiehn selected/opened? (look for patient name in header or patient search)
2. Was an encounter form or clinical documentation opened?
3. Is there evidence of text entry about diet, diabetes education, or nutrition counseling?
4. Does the workflow show navigating through patient chart to documentation?

Respond in JSON format:
{
    "patient_visible": true/false,
    "encounter_opened": true/false,
    "education_entry_visible": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                all_frames = (frames or []) + ([final_frame] if final_frame else [])
                if all_frames:
                    vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                    details['vlm_result'] = vlm_result
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        
                        # Bonus points from VLM verification (up to 10 extra, capped at 100 total)
                        vlm_bonus = 0
                        if parsed.get('patient_visible'):
                            vlm_bonus += 3
                        if parsed.get('encounter_opened'):
                            vlm_bonus += 3
                        if parsed.get('education_entry_visible'):
                            vlm_bonus += 4
                        
                        if vlm_bonus > 0:
                            old_score = score
                            score = min(100, score + vlm_bonus)
                            if score > old_score:
                                feedback_parts.append(f"✅ VLM verification: +{score - old_score} points")
                        
                        logger.info(f"VLM result: {parsed}")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    # Determine pass/fail
    # Must have correct patient AND (new documentation OR education content)
    key_criteria_met = (
        subscores["correct_patient"] and 
        (subscores["newly_created"] or subscores["education_documented"])
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Cap score at 100
    score = min(100, score)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": details
    }