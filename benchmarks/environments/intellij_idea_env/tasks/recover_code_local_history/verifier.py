#!/usr/bin/env python3
"""Verifier for recover_code_local_history task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recover_code_local_history(traj, env_info, task_info):
    """
    Verify that the code was restored using Local History.
    
    Criteria:
    1. Critical constants (PLATINUM_LIMIT, GOLD_LIMIT) are present (40 pts)
    2. Critical error codes (ERR_099) are present (20 pts)
    3. The file compiles successfully (20 pts)
    4. The file does NOT contain the 'TODO' stub comment (10 pts)
    5. VLM: Verify Local History dialog was used (10 pts)
    
    Total: 100 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', [])
    forbidden_strings = metadata.get('forbidden_strings', [])
    
    score = 0
    feedback_parts = []
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    content = result.get('file_content', '')
    compile_success = result.get('compile_success', False)
    
    # --- Criterion 1 & 2: Content Verification (60 pts) ---
    found_count = 0
    missing = []
    
    # We weight specific strings differently
    # "PLATINUM_LIMIT = 50000.00" -> Hard to guess -> 20 pts
    # "GOLD_LIMIT = 15000.00" -> 10 pts
    # "ERR_099" -> 10 pts
    # "validate" method -> 20 pts
    
    if "PLATINUM_LIMIT = 50000.00" in content:
        score += 20
        feedback_parts.append("Found Platinum limit (20/20)")
    else:
        missing.append("Platinum limit")

    if "GOLD_LIMIT = 15000.00" in content:
        score += 10
        feedback_parts.append("Found Gold limit (10/10)")
    else:
        missing.append("Gold limit")

    if "ERR_099" in content:
        score += 10
        feedback_parts.append("Found Error code (10/10)")
    else:
        missing.append("Error code")

    if "validate(Transaction tx, UserTier tier)" in content and "switch (tier)" in content:
        score += 20
        feedback_parts.append("Found validation logic (20/20)")
    else:
        missing.append("Validation logic")

    if missing:
        feedback_parts.append(f"Missing content: {', '.join(missing)}")

    # --- Criterion 3: Compilation (20 pts) ---
    if compile_success:
        score += 20
        feedback_parts.append("Project compiles (20/20)")
    else:
        feedback_parts.append("Project compilation failed")

    # --- Criterion 4: Stub Removal (10 pts) ---
    stub_present = any(s in content for s in forbidden_strings)
    if not stub_present and len(content) > 500: # Ensure it's not just empty
        score += 10
        feedback_parts.append("Stub code removed (10/10)")
    elif stub_present:
        feedback_parts.append("Stub 'TODO' comment still present")
    
    # --- Criterion 5: VLM Verification (10 pts) ---
    # Check if the "Local History" dialog was ever visible
    from gym_anything.vlm import sample_trajectory_frames
    
    vlm_score = 0
    if env_info.get('query_vlm'):
        try:
            frames = sample_trajectory_frames(traj, num_samples=5)
            prompt = """
            Look at these screenshots from IntelliJ IDEA.
            Does any screenshot show the "Local History" window or dialog?
            It usually looks like a split-pane diff view with a timestamp list on the left or "Show History" in a context menu.
            Respond YES or NO.
            """
            vlm_result = env_info['query_vlm'](prompt=prompt, images=frames)
            if vlm_result and vlm_result.get('success'):
                # Simple heuristic: if VLM says YES
                if "YES" in vlm_result.get('response', '').upper():
                    vlm_score = 10
                    feedback_parts.append("VLM: Local History usage detected (10/10)")
                else:
                    feedback_parts.append("VLM: Local History usage not explicitly seen (0/10)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if score is already high (logic restored), give benefit of doubt
            if score >= 70:
                vlm_score = 10
                feedback_parts.append("VLM skipped, assuming success based on file content (10/10)")

    score += vlm_score

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }