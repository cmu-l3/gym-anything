#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ca_import(traj, env_info, task_info):
    """
    Verify that the agent successfully imported the Root CA, configured trust, 
    avoided security overrides, and extracted the target text.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_text = metadata.get('expected_text', 'Tenets of Zero Trust').lower().strip()

    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    cert_imported = result.get('cert_imported', False)
    trust_flags = result.get('trust_flags', '')
    override_used = result.get('override_used', False)
    file_exists = result.get('output_file_exists', False)
    file_content = result.get('file_content', '').lower().strip()
    file_created_during_task = result.get('file_created_during_task', False)

    # CRITERION 1: CA Certificate Imported (40 points)
    if cert_imported:
        score += 40
        feedback_parts.append("Root CA found in cert9.db")
    else:
        feedback_parts.append("Root CA NOT found in cert9.db")

    # CRITERION 2: CA Trust Flags Configured (20 points)
    # The flag 'C' indicates trust to issue certs. For websites it's typically the first flag (e.g., CT,, or C,,)
    has_website_trust = False
    if cert_imported and trust_flags:
        flags = trust_flags.split(',')
        if len(flags) > 0 and 'C' in flags[0]:
            has_website_trust = True
            
    if has_website_trust:
        score += 20
        feedback_parts.append("CA trusted for websites")
    else:
        feedback_parts.append(f"CA lacks website trust (Flags: {trust_flags})")

    # CRITERION 3: No Override Used (20 points)
    # The agent must not cheat by clicking "Accept the Risk and Continue"
    if not override_used:
        score += 20
        feedback_parts.append("No security exceptions used")
    else:
        feedback_parts.append("FAILED: Security exception bypass detected in cert_override.txt")

    # CRITERION 4: Extracted Text (20 points)
    if file_exists and expected_text in file_content:
        if file_created_during_task:
            score += 20
            feedback_parts.append("Correct policy text extracted")
        else:
            feedback_parts.append("Policy text file was stale (not created during task)")
    elif file_exists:
        feedback_parts.append(f"Output file exists but missing expected text '{expected_text}'")
    else:
        feedback_parts.append("Output text file missing")

    # Optional VLM verification for trajectory context
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_prompt = (
                "Did the user open Firefox Settings/Preferences and access the Certificate Manager dialog? "
                "Respond with 'YES' or 'NO'."
            )
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_result and "yes" in vlm_result.lower():
                feedback_parts.append("VLM confirmed Certificate Manager UI interaction")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Determine Pass/Fail
    # Must have imported the cert, established trust, and avoided the override to genuinely pass this networking scenario.
    key_criteria_met = cert_imported and has_website_trust and not override_used
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "cert_imported": cert_imported,
            "has_website_trust": has_website_trust,
            "trust_flags": trust_flags,
            "override_used": override_used,
            "file_exists": file_exists,
            "content_correct": expected_text in file_content
        }
    }