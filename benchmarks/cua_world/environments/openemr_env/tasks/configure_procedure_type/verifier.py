#!/usr/bin/env python3
"""
Verifier for Configure Procedure Type task in OpenEMR

Verifies that a new HbA1c laboratory procedure type was correctly configured.

Verification Criteria:
1. Procedure type exists with HbA1c-related name (30 points)
2. Correct CPT code 83036 (25 points)
3. Result type configured with units (20 points)
4. Standard code (LOINC) is set (10 points)
5. Created during task - anti-gaming (10 points)
6. Description populated (5 points)

Pass Threshold: 55 points (procedure exists + correct CPT code minimum)
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_procedure_type(traj, env_info, task_info):
    """
    Verify that HbA1c procedure type was correctly configured.
    
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
            "feedback": "Copy function not available"
        }
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_code = metadata.get('expected_procedure_code', '83036')
    expected_std_code = metadata.get('expected_standard_code', '4548-4')
    expected_units = metadata.get('expected_units', '%')
    
    # Get scoring weights
    weights = metadata.get('scoring_weights', {
        'procedure_exists': 30,
        'correct_cpt_code': 25,
        'result_type_configured': 20,
        'standard_code_set': 10,
        'created_after_start': 10,
        'description_populated': 5
    })
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_procedure_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "procedure_exists": False,
            "correct_cpt_code": False,
            "result_type_configured": False,
            "standard_code_set": False,
            "created_after_start": False,
            "description_populated": False
        }
        
        # Extract data from result
        proc_found = result.get('procedure_found', False)
        created_during_task = result.get('created_during_task', False)
        procedure = result.get('procedure', {})
        result_type_found = result.get('result_type_found', False)
        result_type = result.get('result_type', {})
        validation = result.get('validation', {})
        
        initial_count = result.get('initial_proc_count', 0)
        current_count = result.get('current_proc_count', 0)
        
        logger.info(f"Procedure found: {proc_found}")
        logger.info(f"Procedure data: {procedure}")
        logger.info(f"Result type found: {result_type_found}")
        logger.info(f"Result type data: {result_type}")
        
        # CRITERION 1: Procedure type exists with HbA1c-related name (30 points)
        if proc_found:
            proc_name = procedure.get('name', '').lower()
            proc_type = procedure.get('type', '')
            
            # Check if name contains HbA1c-related terms
            hba1c_patterns = ['hba1c', 'a1c', 'hemoglobin a', 'glyco', 'glycated']
            name_matches = any(pattern in proc_name for pattern in hba1c_patterns)
            
            if name_matches:
                score += weights['procedure_exists']
                subscores["procedure_exists"] = True
                feedback_parts.append(f"✅ HbA1c procedure type found: '{procedure.get('name')}'")
                
                # Bonus info about type
                if proc_type == 'ord':
                    feedback_parts.append(f"   Type: Orderable procedure (correct)")
                elif proc_type:
                    feedback_parts.append(f"   Type: {proc_type}")
            else:
                # Procedure exists but name doesn't match HbA1c
                score += weights['procedure_exists'] // 2  # Partial credit
                feedback_parts.append(f"⚠️ Procedure found but name doesn't clearly indicate HbA1c: '{procedure.get('name')}'")
        else:
            feedback_parts.append("❌ No HbA1c procedure type found in database")
            # Check if any new procedures were added
            if current_count > initial_count:
                feedback_parts.append(f"   Note: {current_count - initial_count} new procedure(s) added, but none match HbA1c criteria")
        
        # CRITERION 2: Correct CPT code 83036 (25 points)
        if proc_found:
            proc_code = procedure.get('procedure_code', '')
            if proc_code == expected_code:
                score += weights['correct_cpt_code']
                subscores["correct_cpt_code"] = True
                feedback_parts.append(f"✅ Correct CPT code: {proc_code}")
            elif proc_code:
                feedback_parts.append(f"❌ Wrong CPT code: expected {expected_code}, got {proc_code}")
            else:
                feedback_parts.append(f"❌ CPT code not set (expected {expected_code})")
        
        # CRITERION 3: Result type configured with units (20 points)
        if result_type_found:
            result_units = result_type.get('units', '')
            result_range = result_type.get('range', '')
            
            if result_units:
                score += weights['result_type_configured']
                subscores["result_type_configured"] = True
                feedback_parts.append(f"✅ Result type configured with units: {result_units}")
                if result_range:
                    feedback_parts.append(f"   Range: {result_range}")
            else:
                score += weights['result_type_configured'] // 2  # Partial credit
                feedback_parts.append(f"⚠️ Result type exists but units not set")
        else:
            feedback_parts.append("❌ No result type configured for the procedure")
        
        # CRITERION 4: Standard code (LOINC) is set (10 points)
        if proc_found:
            std_code = procedure.get('standard_code', '')
            if std_code and std_code != 'NULL' and len(std_code.strip()) > 0:
                score += weights['standard_code_set']
                subscores["standard_code_set"] = True
                
                # Check if it matches expected LOINC
                if '4548' in std_code:
                    feedback_parts.append(f"✅ Correct LOINC code: {std_code}")
                else:
                    feedback_parts.append(f"✅ Standard code set: {std_code} (expected {expected_std_code})")
            else:
                feedback_parts.append(f"⚠️ Standard code (LOINC) not set")
        
        # CRITERION 5: Created during task - anti-gaming (10 points)
        if created_during_task:
            score += weights['created_after_start']
            subscores["created_after_start"] = True
            feedback_parts.append("✅ Procedure was created during this task session")
        else:
            feedback_parts.append("⚠️ Could not verify procedure was created during task")
            # Don't fail completely for this, but note the concern
        
        # CRITERION 6: Description populated (5 points)
        if proc_found:
            desc = procedure.get('description', '')
            if desc and desc != 'NULL' and len(desc.strip()) > 3:
                score += weights['description_populated']
                subscores["description_populated"] = True
                feedback_parts.append(f"✅ Description provided: {desc[:50]}...")
            else:
                feedback_parts.append("⚠️ Description not populated")
        
        # Calculate pass/fail
        # Must have procedure exists AND correct CPT code to pass
        key_criteria_met = subscores["procedure_exists"] and subscores["correct_cpt_code"]
        passed = score >= 55 and key_criteria_met
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\nScore: {score}/100"
        feedback += f"\nKey criteria met: {key_criteria_met}"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "procedure": procedure,
                "result_type": result_type,
                "created_during_task": created_during_task,
                "counts": {
                    "initial": initial_count,
                    "current": current_count
                }
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Result file not found - export may have failed"
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse result JSON: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }


def verify_with_vlm_fallback(traj, env_info, task_info):
    """
    Enhanced verification that includes VLM trajectory analysis as fallback.
    
    Uses trajectory frames to verify the agent actually navigated to
    procedure configuration and performed the setup.
    """
    # First run database verification
    db_result = verify_configure_procedure_type(traj, env_info, task_info)
    
    # If database verification passed with high confidence, return
    if db_result.get('passed') and db_result.get('score', 0) >= 75:
        return db_result
    
    # Try VLM verification on trajectory
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return db_result
    
    try:
        # Import trajectory sampling utilities
        from gym_anything.vlm import sample_trajectory_frames
        
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=5)
        
        if not frames:
            return db_result
        
        # VLM prompt to verify procedure configuration workflow
        vlm_prompt = """You are verifying if a computer agent successfully configured a new laboratory procedure type in OpenEMR.

TASK: Configure an HbA1c (Hemoglobin A1c) procedure type with CPT code 83036.

Look at these screenshots from the agent's work session and determine:
1. Did the agent navigate to the Procedures Configuration page?
   - Look for: "Procedure/Device Configuration", "Procedures", "Configuration"
   - Admin menu navigation
2. Did the agent add or edit a procedure entry?
   - Look for: Form fields, save buttons, tree-like procedure list
3. Is there evidence of entering HbA1c-related information?
   - Look for: "HbA1c", "A1c", "83036", "Hemoglobin"
4. Did the configuration appear to be saved?
   - Look for: Success messages, list updates

Respond in JSON format:
{
    "navigated_to_procedure_config": true/false,
    "procedure_form_visible": true/false,
    "hba1c_info_entered": true/false,
    "save_action_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
        
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=frames
        )
        
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            
            vlm_score = 0
            vlm_feedback = []
            
            if parsed.get('navigated_to_procedure_config'):
                vlm_score += 10
                vlm_feedback.append("✅ VLM: Navigated to procedure configuration")
            
            if parsed.get('procedure_form_visible'):
                vlm_score += 10
                vlm_feedback.append("✅ VLM: Procedure form visible")
            
            if parsed.get('hba1c_info_entered'):
                vlm_score += 10
                vlm_feedback.append("✅ VLM: HbA1c information entered")
            
            if parsed.get('save_action_visible'):
                vlm_score += 5
                vlm_feedback.append("✅ VLM: Save action detected")
            
            # Combine scores
            combined_score = min(100, db_result.get('score', 0) + vlm_score)
            
            # Adjust pass criteria if VLM provides strong evidence
            if vlm_score >= 25 and db_result.get('score', 0) >= 30:
                db_result['passed'] = True
            
            db_result['score'] = combined_score
            db_result['feedback'] += "\n\n--- VLM Trajectory Analysis ---\n" + "\n".join(vlm_feedback)
            db_result['vlm_verification'] = parsed
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
    
    return db_result