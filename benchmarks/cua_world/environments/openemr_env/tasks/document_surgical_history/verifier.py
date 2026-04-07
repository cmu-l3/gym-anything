#!/usr/bin/env python3
"""
Verifier for Document Surgical History task in OpenEMR

Verifies that a surgical history entry (appendectomy) was correctly documented
for patient Jayson Fadel.

Scoring (100 points total):
- Surgical entry exists with type='surgery': 35 points
- Entry is for correct patient (pid=3): 20 points
- Procedure name contains 'appendectomy': 20 points
- Procedure date is correct (2015-03-22): 15 points
- Entry was created during task (anti-gaming): 10 points

Pass threshold: 70 points (requires entry + correct patient + correct procedure)
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_surgical_history(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that surgical history was documented correctly.
    
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
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    expected_procedure = metadata.get('procedure_name', 'Appendectomy').lower()
    expected_date = metadata.get('procedure_date', '2015-03-22')
    
    # Scoring weights
    weights = metadata.get('scoring_weights', {})
    weight_entry_exists = weights.get('entry_exists', 35)
    weight_correct_patient = weights.get('correct_patient', 20)
    weight_correct_procedure = weights.get('correct_procedure', 20)
    weight_correct_date = weights.get('correct_date', 15)
    weight_newly_created = weights.get('newly_created', 10)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/surgical_history_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "entry_exists": False,
            "correct_patient": False,
            "correct_procedure": False,
            "correct_date": False,
            "newly_created": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_surgery_count', 0)
        current_count = result.get('current_surgery_count', 0)
        appendectomy_found = result.get('appendectomy_found', False)
        entry = result.get('entry', {})
        validation = result.get('validation', {})
        task_start = result.get('task_start_time', 0)
        
        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}")
        logger.info(f"Appendectomy found: {appendectomy_found}")
        logger.info(f"Entry data: {entry}")
        
        # CRITERION 1: Surgical entry exists (35 points)
        if appendectomy_found:
            score += weight_entry_exists
            subscores["entry_exists"] = True
            feedback_parts.append(f"✅ Surgical history entry found (type='surgery')")
        else:
            feedback_parts.append(f"❌ No surgical history entry with 'appendectomy' found")
            
            # Check if any new surgery was added at all
            if current_count > initial_count:
                new_entries = current_count - initial_count
                feedback_parts.append(f"  Note: {new_entries} new surgery entry(ies) added, but none match 'appendectomy'")
                # Partial credit for adding a surgery (but wrong procedure name)
                score += 10
            else:
                feedback_parts.append(f"  No new surgical history entries were created")
            
            # Early return since main criterion failed
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: Correct patient (20 points)
        entry_pid = entry.get('pid', '')
        try:
            entry_pid_int = int(entry_pid) if entry_pid else 0
        except (ValueError, TypeError):
            entry_pid_int = 0
            
        if entry_pid_int == expected_pid:
            score += weight_correct_patient
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Entry linked to correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient: expected pid={expected_pid}, got pid={entry_pid}")
            # Adversarial case - wrong patient is critical failure
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 3: Correct procedure name (20 points)
        entry_title = entry.get('title', '').lower()
        if expected_procedure in entry_title or 'appendix' in entry_title:
            score += weight_correct_procedure
            subscores["correct_procedure"] = True
            feedback_parts.append(f"✅ Procedure name correct: '{entry.get('title', '')}'")
        else:
            feedback_parts.append(f"❌ Procedure name mismatch: expected '{expected_procedure}', got '{entry.get('title', '')}'")
        
        # CRITERION 4: Correct date (15 points)
        entry_date = entry.get('procedure_date', '')
        if entry_date == expected_date:
            score += weight_correct_date
            subscores["correct_date"] = True
            feedback_parts.append(f"✅ Procedure date correct: {expected_date}")
        elif entry_date and '2015' in entry_date:
            # Partial credit for correct year
            partial_points = weight_correct_date // 2
            score += partial_points
            feedback_parts.append(f"⚠️ Procedure date partial match: expected {expected_date}, got {entry_date}")
        else:
            feedback_parts.append(f"❌ Procedure date incorrect: expected {expected_date}, got '{entry_date}'")
        
        # CRITERION 5: Entry was newly created during task (10 points - anti-gaming)
        created_during_task = validation.get('created_during_task', False)
        entry_created_ts = entry.get('created_timestamp', 0)
        
        if created_during_task:
            score += weight_newly_created
            subscores["newly_created"] = True
            feedback_parts.append(f"✅ Entry was created during task execution")
        elif task_start > 0 and entry_created_ts > 0:
            if entry_created_ts > task_start:
                score += weight_newly_created
                subscores["newly_created"] = True
                feedback_parts.append(f"✅ Entry timestamp verified as new")
            else:
                feedback_parts.append(f"⚠️ Entry may have existed before task started")
        else:
            # Check if count increased as alternative verification
            if current_count > initial_count:
                score += weight_newly_created // 2
                feedback_parts.append(f"⚠️ Count increased but timestamp not verified")
            else:
                feedback_parts.append(f"⚠️ Could not verify entry creation time")
        
        # Determine pass/fail
        # Must have: entry exists + correct patient + correct procedure (minimum)
        key_criteria_met = (
            subscores["entry_exists"] and 
            subscores["correct_patient"] and 
            subscores["correct_procedure"]
        )
        passed = score >= 70 and key_criteria_met
        
        # Final feedback summary
        if passed:
            feedback_parts.insert(0, f"✅ SUCCESS: Surgical history documented correctly (Score: {score}/100)")
        elif score >= 50:
            feedback_parts.insert(0, f"⚠️ PARTIAL: Most requirements met (Score: {score}/100)")
        else:
            feedback_parts.insert(0, f"❌ FAIL: Surgical history not properly documented (Score: {score}/100)")
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
        
    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Verification failed: Could not read result file. Export script may not have run."
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification failed: Invalid result JSON - {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }


def verify_with_vlm(traj: Dict[str, Any], env_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Secondary VLM-based verification using trajectory frames.
    
    This provides additional confidence by checking visual evidence
    that the agent navigated to the surgical history section.
    """
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        query_vlm = env_info.get('query_vlm')
        if not query_vlm:
            return {"success": False, "error": "VLM not available"}
        
        # Sample frames from trajectory to verify workflow
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"success": False, "error": "No screenshots available"}
        
        all_frames = frames + ([final] if final else [])
        
        prompt = """Analyze these screenshots from an OpenEMR session to verify if the user documented surgical history.

Look for evidence of:
1. Patient chart was opened (patient name visible)
2. Navigation to Issues/Medical History section
3. A surgical history form or entry being created
4. The word "appendectomy" or "surgery" visible
5. A date field showing 2015 or 2015-03-22

Respond in JSON format:
{
    "patient_chart_opened": true/false,
    "issues_section_accessed": true/false,
    "surgery_form_visible": true/false,
    "appendectomy_mentioned": true/false,
    "date_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
        
        result = query_vlm(prompt=prompt, images=all_frames)
        return result
        
    except ImportError:
        return {"success": False, "error": "VLM utilities not available"}
    except Exception as e:
        return {"success": False, "error": str(e)}


if __name__ == "__main__":
    # For testing outside of gym environment
    import subprocess
    
    def mock_copy(src, dst):
        subprocess.run(f"cp {src} {dst}", shell=True)
    
    # Test with mock data
    test_result = {
        "patient_pid": 3,
        "task_start_time": 1700000000,
        "initial_surgery_count": 0,
        "current_surgery_count": 1,
        "appendectomy_found": True,
        "entry": {
            "id": "1",
            "pid": "3",
            "title": "Appendectomy",
            "procedure_date": "2015-03-22",
            "comments": "Laparoscopic approach",
            "created_timestamp": 1700000100
        },
        "validation": {
            "created_during_task": True,
            "date_correct": True,
            "comments_valid": True
        }
    }
    
    # Write test data
    with open("/tmp/surgical_history_result.json", "w") as f:
        json.dump(test_result, f)
    
    result = verify_surgical_history(
        traj={},
        env_info={"copy_from_env": mock_copy},
        task_info={"metadata": {}}
    )
    
    print(f"Score: {result['score']}")
    print(f"Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")