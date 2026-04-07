#!/usr/bin/env python3
"""
Verifier for configure_pci_compliance_report task.

Multi-modal Verification Strategy:
1. File Verification (40 pts): Checks the text file created by the agent for correct configuration details.
   - Proves the agent "knows" what it configured.
   - Anti-gaming: File must be created AFTER task start.
2. VLM Trajectory Verification (60 pts): Uses visual history to confirm UI actions.
   - Verifies navigation to 'Compliance' > 'PCI-DSS'.
   - Verifies selection of Requirements 7, 8, 10.
   - Verifies Scheduling configuration (Email, Frequency, Format).
"""

import json
import os
import sys
import tempfile
import logging
import re
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_configure_pci_compliance_report(traj, env_info, task_info):
    """
    Verifies the PCI-DSS compliance report configuration task.
    """
    # 1. Setup & Imports
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_email = metadata.get('expected_email', 'compliance-team@acmecorp.com')
    expected_reqs = metadata.get('expected_requirements', ['7', '8', '10'])

    # Helper to load JSON from env
    def load_json_from_env(remote_path):
        local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
        try:
            copy_from_env(remote_path, local_tmp)
            with open(local_tmp, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load {remote_path}: {e}")
            return None
        finally:
            if os.path.exists(local_tmp):
                os.unlink(local_tmp)

    # Load task result
    result_data = load_json_from_env("C:\\workspace\\tasks\\task_result.json")
    if not result_data:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result file."}

    score = 0
    feedback = []

    # =========================================================
    # CRITERION 1: Output File Verification (Max 40 pts)
    # =========================================================
    file_exists = result_data.get('output_file_exists', False)
    file_content = result_data.get('output_file_content', '')
    task_start = result_data.get('task_start_time', 0)
    file_created = result_data.get('output_file_created_timestamp', 0)

    if file_exists:
        # Anti-gaming: Check timestamp
        if file_created > task_start:
            score += 10
            feedback.append("Documentation file created during task.")
            
            # Check Content
            content_lower = file_content.lower()
            
            # Check Email
            if expected_email.lower() in content_lower:
                score += 15
                feedback.append(f"Correct email '{expected_email}' documented.")
            else:
                feedback.append(f"Missing or incorrect email in documentation.")

            # Check Requirements
            reqs_found = [r for r in expected_reqs if r in content_lower]
            if len(reqs_found) == len(expected_reqs):
                score += 15
                feedback.append(f"All required PCI sections ({', '.join(expected_reqs)}) documented.")
            elif len(reqs_found) > 0:
                score += 5 * len(reqs_found)
                feedback.append(f"Some PCI sections documented: {', '.join(reqs_found)}.")
            else:
                feedback.append("No PCI requirement numbers found in documentation.")
        else:
            feedback.append("Documentation file existed before task start (Potential gaming).")
    else:
        feedback.append("Documentation file not found.")

    # =========================================================
    # CRITERION 2: VLM Trajectory Verification (Max 60 pts)
    # =========================================================
    # We need to use the trajectory to verify UI actions since we can't easily query the proprietary DB
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    # Sample frames to capture the workflow
    frames = sample_trajectory_frames(traj, n=8)
    
    if not frames:
         feedback.append("No trajectory frames available for VLM verification.")
    else:
        # Construct VLM Prompt
        prompt = f"""
        You are verifying a user activity in ManageEngine ADAudit Plus.
        The user was asked to:
        1. Navigate to Reports > Compliance > PCI-DSS.
        2. Select Requirements 7, 8, and 10.
        3. Schedule a report (Weekly, PDF, Email: {expected_email}).

        Review the provided screenshots of the user's session.
        
        Answer the following with YES or NO and a brief reason:
        1. Did the user access the 'PCI-DSS' section?
        2. Did the user select or toggle Requirements 7, 8, or 10?
        3. Did the user open the 'Schedule' configuration?
        4. Is the email '{expected_email}' visible in any input field?
        5. Is the frequency set to 'Weekly' or format to 'PDF'?

        Return JSON format:
        {{
            "pci_section_accessed": boolean,
            "requirements_selected": boolean,
            "schedule_configured": boolean,
            "email_correct": boolean,
            "settings_correct": boolean
        }}
        """

        try:
            vlm_response = query_vlm(images=frames, prompt=prompt)
            vlm_data = vlm_response.get('parsed', {})
            
            # Score based on VLM
            if vlm_data.get('pci_section_accessed'):
                score += 10
                feedback.append("VLM: Verified navigation to PCI-DSS section.")
            
            if vlm_data.get('requirements_selected'):
                score += 15
                feedback.append("VLM: Verified requirement selection.")
                
            if vlm_data.get('schedule_configured'):
                score += 10
                feedback.append("VLM: Verified schedule dialog opened.")
                
            if vlm_data.get('email_correct'):
                score += 15
                feedback.append("VLM: Verified correct email entry.")
                
            if vlm_data.get('settings_correct'):
                score += 10
                feedback.append("VLM: Verified schedule settings (Weekly/PDF).")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append("VLM verification failed due to error.")

    # =========================================================
    # Final Scoring
    # =========================================================
    
    # Pass threshold: 60 points
    # Must have at least some file evidence OR strong VLM evidence
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }