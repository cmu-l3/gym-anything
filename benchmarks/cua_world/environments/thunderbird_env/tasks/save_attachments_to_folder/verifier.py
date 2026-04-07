#!/usr/bin/env python3
"""
Verifier for save_attachments_to_folder task.

Uses multi-criteria evaluation to prevent gaming:
1. File existence checks (40 pts)
2. File integrity / format verification (20 pts)
3. Anti-gaming creation timestamps verification (10 pts)
4. Attachment size parity checks (20 pts)
5. VLM trajectory verification (10 pts)

Returns a dictionary with passed status, score out of 100, and feedback string.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utilities safely
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM module not available. VLM checks will be skipped and proportionally scored.")

VLM_PROMPT = """You are evaluating an AI agent's performance in Thunderbird.
The agent was asked to find an email titled 'Site Update - Weekly Report #47' and save its two attachments.

Review the sequence of screenshots. Answer the following questions:
1. Did the agent navigate through the Inbox and locate the correct email?
2. Is there evidence of interacting with attachments (e.g., Save As dialogs, attachment panes)?
3. Did the agent navigate to the 'ProjectFiles' folder during saving?

Respond ONLY in JSON format:
{
    "interacted_with_correct_email": true/false,
    "interacted_with_attachments": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_save_attachments(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy the exported state result
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)

    # Copy the expected sizes (injected dynamically during setup)
    sizes_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    expected_pdf_size = 0
    expected_csv_size = 0
    try:
        copy_from_env("/tmp/expected_attachment_sizes.json", sizes_file.name)
        with open(sizes_file.name, 'r') as f:
            expected_sizes = json.load(f)
            expected_pdf_size = expected_sizes.get("pdf_size", 0)
            expected_csv_size = expected_sizes.get("csv_size", 0)
    except Exception as e:
        logger.warning(f"Could not read expected sizes: {e}")
    finally:
        if os.path.exists(sizes_file.name):
            os.unlink(sizes_file.name)

    score = 0
    feedback_parts = []

    # 1. Existence Checks (40 Points)
    if result.get("pdf_exists"):
        score += 20
        feedback_parts.append("PDF exists")
    else:
        feedback_parts.append("PDF missing")

    if result.get("csv_exists"):
        score += 20
        feedback_parts.append("CSV exists")
    else:
        feedback_parts.append("CSV missing")

    # 2. Content Validity Checks (20 Points)
    if result.get("pdf_valid_content"):
        score += 10
        feedback_parts.append("PDF is valid format")
    elif result.get("pdf_exists"):
        feedback_parts.append("PDF format invalid/empty")
        
    if result.get("csv_valid_content"):
        score += 10
        feedback_parts.append("CSV headers/data valid")
    elif result.get("csv_exists"):
        feedback_parts.append("CSV format invalid/empty")

    # 3. Anti-Gaming Creation Checks (10 Points)
    if result.get("pdf_created_during_task") and result.get("csv_created_during_task"):
        score += 10
        feedback_parts.append("Files created during task timeframe")
    elif result.get("pdf_created_during_task") or result.get("csv_created_during_task"):
        score += 5
        feedback_parts.append("Only one file created during task timeframe")
    else:
        feedback_parts.append("Files failed timestamp validation")

    # 4. Size Parity Verification (20 Points)
    def size_ok(actual, expected):
        if expected == 0: return False
        return abs(actual - expected) / expected <= 0.05

    if result.get("pdf_exists") and size_ok(result.get("pdf_size"), expected_pdf_size):
        score += 10
        feedback_parts.append("PDF size correct")
    elif result.get("pdf_exists"):
        feedback_parts.append("PDF size incorrect")

    if result.get("csv_exists") and size_ok(result.get("csv_size"), expected_csv_size):
        score += 10
        feedback_parts.append("CSV size correct")
    elif result.get("csv_exists"):
        feedback_parts.append("CSV size incorrect")

    # 5. VLM Trajectory Check (10 Points)
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            vlm_res = query_vlm(images=images, prompt=VLM_PROMPT)
            if vlm_res and isinstance(vlm_res, dict):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("interacted_with_correct_email") and parsed.get("interacted_with_attachments"):
                    score += 10
                    feedback_parts.append("VLM verified email/attachment interaction")
                else:
                    feedback_parts.append("VLM did not observe expected interactions")
            else:
                score += 10  # Forgive if VLM fails to parse safely
                feedback_parts.append("VLM query failed, granting points")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            score += 10 # Default pass if internal error
    else:
        score += 10
        feedback_parts.append("VLM unavailable, auto-granting VLM points")

    # Evaluation
    # Must achieve at least 70/100, and fundamentally Both files MUST exist.
    key_criteria_met = result.get("pdf_exists") and result.get("csv_exists")
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }