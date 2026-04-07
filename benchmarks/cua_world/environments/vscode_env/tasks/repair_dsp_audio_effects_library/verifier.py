#!/usr/bin/env python3
"""
Verifier for the repair_dsp_audio_effects_library task.

Checks whether the agent identified and fixed 5 algorithmic bugs in
the audio DSP pipeline.

Each fix is worth 20 points (total 100). Pass threshold: 60.
Includes VLM verification to ensure actual VSCode usage.
"""

import sys
import os
import json
import re
import logging
import tempfile

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _safe_get_content(data, key):
    """Return file content from the result dict, or empty string."""
    files = data.get("files", {})
    file_data = files.get(key, {})
    val = file_data.get("content")
    return val if isinstance(val, str) else ""


def verify_dsp_library(traj, env_info, task_info):
    """
    Verify that the agent found and fixed all 5 DSP bugs.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dsp_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            file_contents = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # ── Bug 1: Sample Rate Hardcoding (dsp/core.py) ──────────
    core_src = _safe_get_content(file_contents, "dsp/core.py")
    if not core_src:
        feedback.append("[-] core.py missing")
    else:
        # Looking for removal of `sample_rate=44100` and replacing with self.sample_rate
        still_hardcoded = bool(re.search(r'sample_rate\s*=\s*44100', core_src))
        uses_dynamic_rate = bool(re.search(r'sample_rate\s*=\s*(?:self\.)?sample_rate', core_src))
        
        if not still_hardcoded and uses_dynamic_rate:
            score += 20
            feedback.append("[+] core.py: Dynamic sample rate fixed (20/20)")
        elif not still_hardcoded:
            score += 10
            feedback.append("[~] core.py: 44100 removed but dynamic propagation unclear (10/20)")
        else:
            feedback.append("[-] core.py: Effects still hardcoded to 44100 Hz (0/20)")

    # ── Bug 2: Delay Buffer Overrun (dsp/effects/delay.py) ──────────
    delay_src = _safe_get_content(file_contents, "dsp/effects/delay.py")
    if not delay_src:
        feedback.append("[-] delay.py missing")
    else:
        # Look for modulo logic on write_ptr: self.write_ptr %= self.buffer_size
        has_modulo = bool(re.search(r'self\.write_ptr\s*%=\s*self\.buffer_size', delay_src))
        has_modulo_alt = bool(re.search(r'self\.write_ptr\s*=\s*\(?self\.write_ptr\s*\+\s*1\)?\s*%\s*self\.buffer_size', delay_src))
        has_if_wrap = bool(re.search(r'if\s+self\.write_ptr\s*>=\s*self\.buffer_size\s*:\s*self\.write_ptr\s*=\s*0', delay_src))
        
        if has_modulo or has_modulo_alt or has_if_wrap:
            score += 20
            feedback.append("[+] delay.py: Circular buffer overrun fixed (20/20)")
        else:
            feedback.append("[-] delay.py: Write pointer still lacks wrap-around logic (0/20)")

    # ── Bug 3: DC Offset in Distortion (dsp/effects/distortion.py) ──────────
    dist_src = _safe_get_content(file_contents, "dsp/effects/distortion.py")
    if not dist_src:
        feedback.append("[-] distortion.py missing")
    else:
        # original code ends with `... + 0.25`
        has_offset = bool(re.search(r'\+\s*0\.25', dist_src))
        # ensure they didn't just delete the whole line
        has_where = bool(re.search(r'np\.where', dist_src))
        
        if not has_offset and has_where:
            score += 20
            feedback.append("[+] distortion.py: DC offset removed (20/20)")
        elif not has_where:
            feedback.append("[-] distortion.py: np.where logic removed, potentially breaking algorithm (0/20)")
        else:
            feedback.append("[-] distortion.py: DC offset (+ 0.25) still present (0/20)")

    # ── Bug 4: Zipper Noise / Interpolation (dsp/effects/chorus.py) ──────────
    chorus_src = _safe_get_content(file_contents, "dsp/effects/chorus.py")
    if not chorus_src:
        feedback.append("[-] chorus.py missing")
    else:
        # Check for fractional logic instead of pure int cast
        has_int_cast = bool(re.search(r'idx\s*=\s*int\s*\(\s*read_ptr\s*\)\s*%\s*self\.buffer_size', chorus_src))
        has_frac_math = bool(re.search(r'frac|1\s*-\s*frac|read_ptr\s*-\s*int', chorus_src))
        has_two_taps = bool(re.search(r'idx\s*\+\s*1|idx1.*idx2', chorus_src))
        
        if has_frac_math and has_two_taps:
            score += 20
            feedback.append("[+] chorus.py: Linear interpolation added (20/20)")
        elif not has_int_cast and has_frac_math:
            score += 15
            feedback.append("[~] chorus.py: Fractional logic detected but incomplete interpolation (15/20)")
        else:
            feedback.append("[-] chorus.py: Still uses int truncation, causing zipper noise (0/20)")

    # ── Bug 5: PCM Bit-Depth Truncation (dsp/core.py) ──────────
    if not core_src:
        feedback.append("[-] core.py missing for Bug 5")
    else:
        # Look for np.round() before astype
        has_round = bool(re.search(r'np\.round\s*\(', core_src) or re.search(r'round\s*\(', core_src))
        has_truncation_only = bool(re.search(r'\(\s*data\s*\*\s*32767\s*\)\.astype', core_src))
        
        if has_round:
            score += 20
            feedback.append("[+] core.py: PCM export applies proper rounding (20/20)")
        elif has_truncation_only:
            feedback.append("[-] core.py: PCM export still truncates bits (0/20)")
        else:
            feedback.append("[-] core.py: PCM export rounding logic unclear (0/20)")

    # ── VLM Trajectory Verification ──────────
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = (
                "You are reviewing the trajectory of an AI agent attempting a coding task in VS Code. "
                "The task involves fixing math bugs in a Python Audio DSP library. "
                "Based on these screenshots, did the agent actively edit code in VS Code or interact with the terminal? "
                "Respond in JSON format: {\"actively_coded\": true/false, \"reasoning\": \"...\"}"
            )
            
            vlm_resp = query_vlm(images=images, prompt=prompt)
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                vlm_passed = parsed.get("actively_coded", False)
                if not vlm_passed:
                    feedback.append("[-] VLM indicates no active coding was performed (Anti-Gaming Check Failed)")
                    score = 0  # Zero out score if no work was done
                else:
                    feedback.append("[+] VLM confirmed active coding in VS Code")
            else:
                feedback.append("[~] VLM query failed, skipping anti-gaming check")

    # Final logic
    tests_passed = file_contents.get("tests_passed", False)
    if tests_passed:
        feedback.append("[+] All unit tests pass!")
    else:
        feedback.append("[-] Unit tests did not fully pass")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "test_output": file_contents.get("test_output", ""),
            "vlm_passed": vlm_passed
        }
    }