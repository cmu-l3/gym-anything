#!/usr/bin/env python3
"""Verifier for interim_data_extract task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """Examine the trajectory and final screenshot of OpenClinica.

Check the following about the user's progress in extracting data:
1. Is OpenClinica visible?
2. Did the user navigate to the 'Extract Data' or 'Create Dataset' module?
3. Is there evidence that the user interacted with the dataset wizard (naming the dataset, selecting CRF items, or configuring export formats)?
4. Is there a 'Download' button, a generated extract file list, or a success message indicating an extract was run?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "extract_module_used": true/false,
    "dataset_wizard_interacted": true/false,
    "extract_run_or_downloaded": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_interim_data_extract(traj, env_info, task_info):
    """
    Verify interim_data_extract task completion.
    
    Scoring Breakdown (100 Points Total):
    - Dataset definition created with correct name: 25 pts
    - CRF items successfully mapped to dataset: 20 pts
    - Export job executed in database: 25 pts
    - Export file successfully generated/downloaded to filesystem: 15 pts
    - VLM trajectory verification: up to 15 pts
    - Audit Log anti-gaming penalty: -20 pts if no GUI interaction detected.
    
    Pass threshold: 60 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Read Results JSON ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/interim_data_extract_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Integrity Check ---
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get('result_nonce', '')
    if expected_nonce and result_nonce != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Nonce mismatch"}

    score = 0
    feedback_parts = []
    
    # 1. Dataset exists
    if result.get("dataset_exists", False):
        score += 25
        feedback_parts.append(f"Dataset created '{result.get('dataset_name')}' (+25)")
    else:
        feedback_parts.append("FAIL: Target dataset 'DM2024_Interim_Vitals' not found (0/25)")
        
    # 2. Items mapped
    if result.get("dataset_items_mapped", False):
        score += 20
        feedback_parts.append("CRF items correctly mapped to dataset (+20)")
    else:
        feedback_parts.append("Dataset missing mapped items (0/20)")
        
    # 3. DB Export job
    if result.get("export_job_exists", False):
        score += 25
        feedback_parts.append("Export job executed successfully (+25)")
    else:
        feedback_parts.append("No export job found in DB (0/25)")
        
    # 4. Filesystem check
    local_found = result.get("local_export_found", False)
    container_found = result.get("container_export_found", False)
    if local_found or container_found:
        score += 15
        loc = "local Downloads" if local_found else "container data directory"
        feedback_parts.append(f"Exported data file found in {loc} (+15)")
    else:
        feedback_parts.append("No generated extract file found on filesystem (0/15)")

    # 5. VLM Visual Verification (using trajectory frames if possible, else fallback to final)
    if query_vlm:
        try:
            # Safely attempt to import frame samplers, fallback if framework missing
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
        except ImportError:
            images = [step['obs']['screenshot'] for step in traj[-3:] if 'screenshot' in step['obs']]

        if images:
            vlm_result = query_vlm(prompt=_build_vlm_prompt(), images=images)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                vlm_score = 0
                if parsed.get("extract_module_used"):
                    vlm_score += 5
                if parsed.get("dataset_wizard_interacted"):
                    vlm_score += 5
                if parsed.get("extract_run_or_downloaded"):
                    vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM verified trajectory progression (+{vlm_score})")

    # 6. Audit Log Anti-gaming Penalty
    audit_baseline = int(result.get("audit_baseline", 0))
    audit_current = int(result.get("audit_current", 0))
    if audit_current <= audit_baseline and score > 0:
        score = max(0, score - 20)
        feedback_parts.append("PENALTY: No GUI audit logs detected (direct DB manipulation suspected) (-20)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }