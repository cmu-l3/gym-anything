#!/usr/bin/env python3
"""
Verifier for Close Patient Encounter task in OpenEMR

This verifies that the agent successfully closed/finalized an open encounter
for patient Elena Schroeder (pid=6) dated 2019-10-15.

Verification Strategy:
1. PRIMARY: Database check - encounter's last_level_closed field should be > 0
2. SECONDARY: VLM trajectory analysis to verify workflow was followed

Scoring:
- Patient chart accessed (VLM): 15 points
- Encounter list viewed (VLM): 15 points  
- Correct encounter opened (VLM): 20 points
- Close action executed (VLM): 25 points
- Encounter status changed in DB: 25 points

Pass threshold: 75 points with database status change required
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# VLM prompts for trajectory verification
VLM_PROMPT_PATIENT_ACCESS = """Analyze this screenshot from OpenEMR (Electronic Health Records system).

Question: Does this screenshot show that the user has accessed a patient's chart or is viewing patient information?

Look for:
- Patient name visible (especially "Elena Schroeder" or similar)
- Patient demographic information displayed
- Patient chart/summary view
- Any indication of being in a patient's medical record

Respond in JSON format:
{
    "patient_chart_visible": true/false,
    "patient_name_visible": "name if visible or null",
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

VLM_PROMPT_ENCOUNTER_LIST = """Analyze this screenshot from OpenEMR (Electronic Health Records system).

Question: Does this screenshot show a list of patient encounters/visits?

Look for:
- List or table of encounters/visits
- Dates of visits
- Encounter history section
- Visit records

Respond in JSON format:
{
    "encounter_list_visible": true/false,
    "encounter_dates_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

VLM_PROMPT_ENCOUNTER_OPEN = """Analyze this screenshot from OpenEMR (Electronic Health Records system).

Question: Does this screenshot show an open/detailed view of a specific patient encounter?

Look for:
- Encounter details displayed (date, reason, notes)
- Clinical forms or documentation
- Encounter-specific information
- Date around October 2019 or "2019-10-15"

Respond in JSON format:
{
    "encounter_detail_view": true/false,
    "encounter_date_matches": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

VLM_PROMPT_CLOSE_ACTION = """Analyze this screenshot from OpenEMR (Electronic Health Records system).

Question: Does this screenshot show evidence that a close/sign/finalize action was performed on an encounter?

Look for:
- "Close", "Sign", "Finalize", "Complete" buttons being clicked or already clicked
- Success messages indicating encounter was closed
- Status changes showing encounter is now closed/finalized
- Confirmation dialogs for closing encounters

Respond in JSON format:
{
    "close_action_visible": true/false,
    "success_message_visible": true/false,
    "status_shows_closed": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""


def verify_close_encounter(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the encounter was successfully closed.
    
    Args:
        traj: Trajectory data with frames/screenshots
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'subscores'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 6)
    expected_fname = metadata.get('patient_fname', 'Elena')
    expected_lname = metadata.get('patient_lname', 'Schroeder')
    encounter_date = metadata.get('encounter_date', '2019-10-15')
    scoring_weights = metadata.get('scoring_weights', {})
    
    score = 0
    feedback_parts = []
    subscores = {
        "patient_chart_accessed": False,
        "encounter_list_viewed": False,
        "correct_encounter_opened": False,
        "close_action_executed": False,
        "encounter_status_changed": False
    }
    
    # =========================================================================
    # PRIMARY VERIFICATION: Database state check
    # =========================================================================
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/close_encounter_result.json", temp_result.name)
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
            "feedback": f"Failed to read verification data: {e}",
            "subscores": subscores
        }
    
    # Extract result data
    encounter_found = result.get('encounter_found', False)
    encounter_closed = result.get('encounter_is_closed', False)
    encounter_data = result.get('encounter', {})
    task_start = result.get('task_start_timestamp', 0)
    initial_state = result.get('initial_state', '')
    
    logger.info(f"Result: found={encounter_found}, closed={encounter_closed}")
    logger.info(f"Encounter data: {encounter_data}")
    logger.info(f"Initial state: {initial_state}")
    
    # Verify correct patient
    enc_pid = encounter_data.get('pid', '')
    try:
        enc_pid_int = int(enc_pid) if enc_pid else 0
    except (ValueError, TypeError):
        enc_pid_int = 0
        
    if enc_pid_int != expected_pid:
        feedback_parts.append(f"Wrong patient! Expected pid={expected_pid}, got {enc_pid}")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # Check encounter closure status (CRITICAL - 25 points)
    if encounter_closed:
        closed_level = encounter_data.get('last_level_closed', '0')
        score += scoring_weights.get('encounter_status_changed', 25)
        subscores["encounter_status_changed"] = True
        feedback_parts.append(f"✅ Encounter successfully closed (last_level_closed={closed_level})")
    else:
        closed_level = encounter_data.get('last_level_closed', '0')
        feedback_parts.append(f"❌ Encounter still OPEN (last_level_closed={closed_level})")
    
    # =========================================================================
    # SECONDARY VERIFICATION: VLM trajectory analysis
    # =========================================================================
    
    if query_vlm:
        try:
            # Get trajectory frames for analysis
            frames = traj.get('frames', [])
            
            # Sample frames from trajectory (beginning, middle, end)
            sampled_frames = []
            if len(frames) >= 5:
                indices = [0, len(frames)//4, len(frames)//2, 3*len(frames)//4, len(frames)-1]
                sampled_frames = [frames[i] for i in indices if i < len(frames)]
            else:
                sampled_frames = frames
            
            logger.info(f"Analyzing {len(sampled_frames)} trajectory frames with VLM")
            
            # Track what we found across trajectory
            found_patient_chart = False
            found_encounter_list = False
            found_encounter_detail = False
            found_close_action = False
            
            for idx, frame in enumerate(sampled_frames):
                frame_path = frame.get('path') if isinstance(frame, dict) else frame
                if not frame_path or not os.path.exists(str(frame_path)):
                    continue
                
                # Check for patient chart access
                if not found_patient_chart:
                    vlm_result = query_vlm(
                        prompt=VLM_PROMPT_PATIENT_ACCESS,
                        image=str(frame_path)
                    )
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if parsed.get('patient_chart_visible'):
                            found_patient_chart = True
                            patient_name = parsed.get('patient_name_visible', '')
                            logger.info(f"Frame {idx}: Patient chart detected - {patient_name}")
                
                # Check for encounter list
                if not found_encounter_list:
                    vlm_result = query_vlm(
                        prompt=VLM_PROMPT_ENCOUNTER_LIST,
                        image=str(frame_path)
                    )
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if parsed.get('encounter_list_visible'):
                            found_encounter_list = True
                            logger.info(f"Frame {idx}: Encounter list detected")
                
                # Check for encounter detail view
                if not found_encounter_detail:
                    vlm_result = query_vlm(
                        prompt=VLM_PROMPT_ENCOUNTER_OPEN,
                        image=str(frame_path)
                    )
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if parsed.get('encounter_detail_view'):
                            found_encounter_detail = True
                            logger.info(f"Frame {idx}: Encounter detail view detected")
                
                # Check for close action (check later frames more likely)
                if not found_close_action and idx >= len(sampled_frames) // 2:
                    vlm_result = query_vlm(
                        prompt=VLM_PROMPT_CLOSE_ACTION,
                        image=str(frame_path)
                    )
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if parsed.get('close_action_visible') or parsed.get('success_message_visible') or parsed.get('status_shows_closed'):
                            found_close_action = True
                            logger.info(f"Frame {idx}: Close action detected")
            
            # Score VLM findings
            if found_patient_chart:
                score += scoring_weights.get('patient_chart_accessed', 15)
                subscores["patient_chart_accessed"] = True
                feedback_parts.append("✅ Patient chart accessed (VLM)")
            else:
                feedback_parts.append("⚠️ Patient chart access not detected (VLM)")
            
            if found_encounter_list:
                score += scoring_weights.get('encounter_list_viewed', 15)
                subscores["encounter_list_viewed"] = True
                feedback_parts.append("✅ Encounter list viewed (VLM)")
            else:
                feedback_parts.append("⚠️ Encounter list view not detected (VLM)")
            
            if found_encounter_detail:
                score += scoring_weights.get('correct_encounter_opened', 20)
                subscores["correct_encounter_opened"] = True
                feedback_parts.append("✅ Encounter detail opened (VLM)")
            else:
                feedback_parts.append("⚠️ Encounter detail view not detected (VLM)")
            
            if found_close_action:
                score += scoring_weights.get('close_action_executed', 25)
                subscores["close_action_executed"] = True
                feedback_parts.append("✅ Close action executed (VLM)")
            else:
                feedback_parts.append("⚠️ Close action not detected (VLM)")
                
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {e}")
            # Give partial credit if database shows success but VLM failed
            if encounter_closed:
                score += 30  # Give some credit for workflow steps
                feedback_parts.append("Partial credit for workflow (VLM unavailable)")
    else:
        # No VLM available - give partial credit if database shows success
        if encounter_closed:
            score += 50  # Give credit for workflow steps
            subscores["patient_chart_accessed"] = True
            subscores["encounter_list_viewed"] = True
            subscores["correct_encounter_opened"] = True
            feedback_parts.append("VLM not available - partial credit based on database result")
    
    # =========================================================================
    # FINAL SCORING
    # =========================================================================
    
    # Key criterion: encounter must be closed in database
    key_criterion_met = subscores["encounter_status_changed"]
    
    # Pass threshold: 75 points AND database shows closed
    passed = score >= 75 and key_criterion_met
    
    # If database shows closed but score is low, ensure minimum pass
    if key_criterion_met and score < 75:
        feedback_parts.append("Note: Encounter closed but workflow verification incomplete")
    
    # If database doesn't show closed, definite fail regardless of score
    if not key_criterion_met:
        passed = False
        feedback_parts.append("CRITICAL: Encounter was not closed in database")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "expected_patient": f"{expected_fname} {expected_lname} (pid={expected_pid})",
            "encounter_date": encounter_date,
            "encounter_closed": encounter_closed,
            "closed_level": encounter_data.get('last_level_closed', '0')
        }
    }