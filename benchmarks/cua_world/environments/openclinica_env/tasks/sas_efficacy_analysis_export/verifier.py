#!/usr/bin/env python3
"""Verifier for sas_efficacy_analysis_export task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import query_vlm as _query_vlm_direct, sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """Examine these trajectory frames from a Linux desktop running OpenClinica and file manager/terminal.

Check the following:
1. Did the user navigate to the "Extract Data" or "Dataset Builder" module in OpenClinica?
2. Is there evidence of selecting a "SAS data and syntax" export format?
3. Did the user use a file manager or terminal to extract/unzip files into a folder called "SAS_Analysis"?

Respond in JSON format:
{
    "dataset_builder_used": true/false,
    "sas_format_selected": true/false,
    "unzip_operation_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_sas_efficacy_analysis_export(traj, env_info, task_info):
    """
    Verify SAS Dataset Export task completion.

    Scoring Breakdown (100 points total):
    - Dataset 'SAS_Efficacy_Data' exists: 20 pts
    - Included Vital Signs & Lab Results: 20 pts
    - Excluded Demographics & Adverse Events: 20 pts
    - SAS Files Extracted to local dir: 25 pts
    - VLM Trajectory Check: 15 pts
    - Audit log penalty: -25 pts if no GUI interaction

    Pass threshold: 75 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/sas_export_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce
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

    # 2. Check Dataset Exists (20 pts)
    if result.get('dataset_exists'):
        score += 20
        feedback_parts.append("✅ Dataset 'SAS_Efficacy_Data' created (+20)")
    else:
        feedback_parts.append("❌ Dataset 'SAS_Efficacy_Data' not found (0/20)")

    # 3. Check Mapped CRFs (Included & Excluded)
    included_crfs_str = result.get('included_crfs', '').lower()
    included_list = [crf.strip() for crf in included_crfs_str.split(',') if crf.strip()]
    
    # Included checks (20 pts)
    has_vital_signs = any('vital' in crf for crf in included_list)
    has_lab_results = any('lab' in crf for crf in included_list)
    
    if has_vital_signs and has_lab_results:
        score += 20
        feedback_parts.append("✅ Vital Signs and Lab Results correctly included (+20)")
    elif has_vital_signs or has_lab_results:
        score += 10
        feedback_parts.append("⚠️ Only one of the required CRFs included (+10)")
    else:
        feedback_parts.append("❌ Vital Signs/Lab Results not included in dataset (0/20)")

    # Excluded checks (20 pts)
    has_demographics = any('demo' in crf for crf in included_list)
    has_adverse_events = any('adverse' in crf for crf in included_list)
    
    if not has_demographics and not has_adverse_events and result.get('dataset_exists'):
        score += 20
        feedback_parts.append("✅ Demographics and Adverse Events correctly excluded (+20)")
    elif (has_demographics or has_adverse_events) and result.get('dataset_exists'):
        feedback_parts.append("❌ Demographics or Adverse Events incorrectly included (0/20)")

    # 4. Check Filesystem Artifacts (25 pts)
    sas_dir_exists = result.get('sas_dir_exists', False)
    sas_file_count = result.get('sas_file_count', 0)
    
    if sas_dir_exists and sas_file_count > 0:
        score += 25
        feedback_parts.append(f"✅ SAS files successfully extracted to analysis directory ({sas_file_count} files) (+25)")
    elif sas_dir_exists:
        score += 5
        feedback_parts.append("⚠️ SAS_Analysis directory created but no .sas files found (+5)")
    else:
        feedback_parts.append("❌ Target SAS_Analysis directory / files missing (0/25)")

    # 5. VLM Verification (15 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            frames.append(final_screenshot)
            
        vlm_result = query_vlm(prompt=_build_vlm_prompt(), images=frames)
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            vlm_score = 0
            if parsed.get('dataset_builder_used'): vlm_score += 5
            if parsed.get('sas_format_selected'): vlm_score += 5
            if parsed.get('unzip_operation_visible'): vlm_score += 5
            score += vlm_score
            feedback_parts.append(f"✅ VLM Trajectory check awarded {vlm_score}/15 pts")
        else:
            feedback_parts.append("⚠️ VLM verification failed to process")

    # 6. Audit Log Check
    baseline = result.get('audit_baseline', 0)
    current = result.get('audit_current', 0)
    if current <= baseline and score > 0:
        score -= 25
        feedback_parts.append("❌ PENALTY: No GUI audit logs detected (-25)")

    passed = score >= 75
    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback_parts)
    }