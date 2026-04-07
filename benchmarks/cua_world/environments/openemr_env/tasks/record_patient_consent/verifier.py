#!/usr/bin/env python3
"""
Verifier for Record Patient Consent task in OpenEMR

Verifies that a consent document was properly recorded for patient Jayson Fadel.

Verification Strategy:
1. PRIMARY: Database verification via exported JSON
   - Check documents table for new entries
   - Check onsite_documents table
   - Check forms table
   
2. SECONDARY: VLM trajectory verification
   - Verify agent navigated to patient chart
   - Verify documents section was accessed
   - Verify document creation workflow was completed

Scoring (100 points):
- Patient correctly selected (15 pts)
- Documents section accessed (20 pts)  
- New document/form created (30 pts)
- Document is consent-related (15 pts)
- Document dated appropriately (10 pts)
- VLM trajectory confirmation (10 pts)
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_record_consent(traj, env_info, task_info):
    """
    Verify that a consent document was recorded for the patient.
    
    Args:
        traj: Trajectory data with frames and steps
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback', 'subscores'
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
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    
    score = 0
    feedback_parts = []
    subscores = {
        "patient_selected": False,
        "documents_accessed": False,
        "new_document_created": False,
        "consent_related": False,
        "dated_correctly": False,
        "vlm_verified": False
    }
    
    # Try to load exported result
    result = None
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/consent_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.warning(f"Could not load result JSON: {e}")
        feedback_parts.append(f"Could not load export result: {e}")
    
    if result:
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        task_start = result.get('task_start_timestamp', 0)
        doc_count_increased = result.get('document_count_increased', False)
        any_new_doc = result.get('any_new_document', False)
        counts = result.get('counts', {})
        new_doc = result.get('new_document', {})
        new_form = result.get('new_form', {})
        new_onsite = result.get('new_onsite_document', {})
        validation = result.get('validation', {})
        
        logger.info(f"Result: pid={patient_pid}, doc_count_increased={doc_count_increased}")
        logger.info(f"New doc: {new_doc}")
        logger.info(f"New form: {new_form}")
        
        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["patient_selected"] = True
            feedback_parts.append(f"✓ Correct patient selected (pid={expected_pid})")
        else:
            feedback_parts.append(f"✗ Wrong patient (expected pid={expected_pid}, got {patient_pid})")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: Documents/forms section accessed (20 points)
        # Evidence: any change in document/form counts or new doc found
        docs_initial = counts.get('documents', {}).get('initial', 0)
        docs_current = counts.get('documents', {}).get('current', 0)
        onsite_initial = counts.get('onsite_documents', {}).get('initial', 0)
        onsite_current = counts.get('onsite_documents', {}).get('current', 0)
        forms_initial = counts.get('forms', {}).get('initial', 0)
        forms_current = counts.get('forms', {}).get('current', 0)
        
        # If any counts increased, documents area was accessed and modified
        if doc_count_increased or any_new_doc:
            score += 20
            subscores["documents_accessed"] = True
            feedback_parts.append("✓ Documents section accessed and modified")
        else:
            # Partial credit if we can infer from trajectory
            feedback_parts.append("△ No document changes detected - may not have accessed documents section")
        
        # CRITERION 3: New document created (30 points)
        doc_found = new_doc.get('found', False)
        form_found = new_form.get('found', False)
        onsite_found = new_onsite.get('found', False)
        
        if doc_found or form_found or onsite_found:
            score += 30
            subscores["new_document_created"] = True
            
            if doc_found:
                doc_name = new_doc.get('name', 'Unknown')
                doc_category = new_doc.get('category', 'Unknown')
                feedback_parts.append(f"✓ New document created: '{doc_name}' (category: {doc_category})")
            elif form_found:
                form_name = new_form.get('name', 'Unknown')
                feedback_parts.append(f"✓ New form created: '{form_name}'")
            elif onsite_found:
                onsite_name = new_onsite.get('name', 'Unknown')
                feedback_parts.append(f"✓ New onsite document created: '{onsite_name}'")
        else:
            # Check if count increased but couldn't identify specific doc
            if docs_current > docs_initial:
                score += 20  # Partial credit
                subscores["new_document_created"] = True
                feedback_parts.append(f"△ Document count increased ({docs_initial} → {docs_current}) but details not captured")
            elif forms_current > forms_initial:
                score += 20  # Partial credit
                subscores["new_document_created"] = True
                feedback_parts.append(f"△ Forms count increased ({forms_initial} → {forms_current}) but details not captured")
            elif onsite_current > onsite_initial:
                score += 20  # Partial credit
                subscores["new_document_created"] = True
                feedback_parts.append(f"△ Onsite docs count increased ({onsite_initial} → {onsite_current})")
            else:
                feedback_parts.append("✗ No new document or form was created")
        
        # CRITERION 4: Document is consent-related (15 points)
        is_consent = validation.get('is_consent_related', False)
        
        # Also check manually
        doc_name_lower = (new_doc.get('name', '') + ' ' + 
                         new_doc.get('category', '') + ' ' +
                         new_form.get('name', '')).lower()
        
        consent_keywords = ['consent', 'authorization', 'agreement', 'permission', 
                           'hipaa', 'treatment', 'patient information']
        
        manual_consent_check = any(kw in doc_name_lower for kw in consent_keywords)
        
        if is_consent or manual_consent_check:
            score += 15
            subscores["consent_related"] = True
            feedback_parts.append("✓ Document appears to be consent-related")
        elif doc_found or form_found:
            # Document exists but not clearly consent - partial credit
            score += 5
            feedback_parts.append("△ Document created but not clearly labeled as consent")
        else:
            feedback_parts.append("✗ Could not verify document is consent-related")
        
        # CRITERION 5: Document dated appropriately (10 points)
        is_today = validation.get('is_dated_today', False)
        doc_date = new_doc.get('date', '') or new_form.get('date', '')
        
        if is_today:
            score += 10
            subscores["dated_correctly"] = True
            feedback_parts.append("✓ Document dated today")
        elif doc_date:
            # Check if date is reasonable (within last hour)
            try:
                today = datetime.now().strftime('%Y-%m-%d')
                if today in doc_date:
                    score += 10
                    subscores["dated_correctly"] = True
                    feedback_parts.append(f"✓ Document date: {doc_date}")
                else:
                    score += 5  # Partial - document exists with some date
                    feedback_parts.append(f"△ Document date ({doc_date}) may not be today")
            except:
                score += 5
                feedback_parts.append(f"△ Document has date: {doc_date}")
        elif subscores["new_document_created"]:
            # New doc created but no date info - give partial credit
            score += 5
            feedback_parts.append("△ Document created but date not captured")
    
    # CRITERION 6: VLM trajectory verification (10 points)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Sample frames from trajectory
            frames = traj.get('frames', [])
            if frames and len(frames) > 0:
                # Get frames from different points in trajectory
                sample_indices = [0, len(frames)//3, 2*len(frames)//3, -1]
                sample_frames = []
                for idx in sample_indices:
                    try:
                        if idx < 0:
                            idx = len(frames) + idx
                        if 0 <= idx < len(frames):
                            sample_frames.append(frames[idx])
                    except:
                        pass
                
                if sample_frames:
                    vlm_prompt = """Analyze these screenshots from a task in OpenEMR medical records system.

The task was to: Record a consent document for patient Jayson Fadel.

Look at the trajectory and determine:
1. Did the agent navigate to a patient chart/record?
2. Did the agent access a Documents, Forms, or similar section?
3. Did the agent appear to create or upload a document?
4. Was there any indication of completing a consent-related action?

Respond in JSON format:
{
    "patient_chart_accessed": true/false,
    "documents_section_visible": true/false,
    "document_creation_activity": true/false,
    "task_appears_completed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
                    
                    vlm_result = query_vlm(
                        prompt=vlm_prompt,
                        images=sample_frames
                    )
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        
                        patient_accessed = parsed.get('patient_chart_accessed', False)
                        docs_visible = parsed.get('documents_section_visible', False)
                        creation_activity = parsed.get('document_creation_activity', False)
                        appears_completed = parsed.get('task_appears_completed', False)
                        confidence = parsed.get('confidence', 'low')
                        
                        # Score based on VLM findings
                        vlm_criteria = sum([patient_accessed, docs_visible, 
                                           creation_activity, appears_completed])
                        
                        if vlm_criteria >= 3 and confidence in ['medium', 'high']:
                            vlm_score = 10
                            subscores["vlm_verified"] = True
                            feedback_parts.append("✓ VLM confirms task workflow completed")
                        elif vlm_criteria >= 2:
                            vlm_score = 5
                            feedback_parts.append("△ VLM shows partial task completion")
                        else:
                            feedback_parts.append(f"△ VLM verification inconclusive: {parsed.get('reasoning', 'unknown')}")
                        
                        logger.info(f"VLM result: {parsed}")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"△ VLM verification error: {str(e)[:50]}")
    
    score += vlm_score
    
    # Determine pass/fail
    # Must have: correct patient + some new document created
    key_criteria = subscores["patient_selected"] and subscores["new_document_created"]
    passed = score >= 50 and key_criteria
    
    # Bonus: if score is close and VLM confirms, pass
    if score >= 45 and subscores["vlm_verified"] and subscores["patient_selected"]:
        passed = True
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "expected_patient": f"{expected_fname} {expected_lname} (pid={expected_pid})",
            "result_loaded": result is not None
        }
    }


if __name__ == "__main__":
    # Test mode
    print("Verifier for record_patient_consent task")
    print("Run via gym-anything framework for actual verification")