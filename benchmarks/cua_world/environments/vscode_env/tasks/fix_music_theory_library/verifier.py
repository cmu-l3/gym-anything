#!/usr/bin/env python3
"""
Verifier for the fix_music_theory_library task.

Checks whether the agent fixed the 5 music theory domain bugs.
Uses static analysis (regex) + pytest test outputs collected from the container.

Each fix is worth 20 points (total 100). Pass threshold: 60.
"""

import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_music_theory_library(traj, env_info, task_info):
    """
    Verify that the agent found and fixed all 5 music theory bugs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='music_verify_')

    try:
        result_src = "/tmp/music_theory_result.json"
        local_result = os.path.join(temp_dir, "music_theory_result.json")

        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            logger.error(f"Failed to copy result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access result file: {str(e)}"
            }

        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found or empty"
            }

        with open(local_result, 'r') as f:
            data = json.load(f)

        files = data.get("files", {})
        test_output = data.get("test_output", "")
        
        score = 0
        feedback = []

        # ── Bug 1: interval_semitones wrap-around ──────────
        ic_content = files.get("music_theory/interval_calculator.py", "")
        if ic_content:
            # Check if % 12 was added
            has_modulo = bool(re.search(r'%\s*12', ic_content))
            buggy_return = bool(re.search(r'return\s+note2\.pitch_class\s*-\s*note1\.pitch_class\s*$', ic_content, re.MULTILINE))
            
            if has_modulo and not buggy_return:
                score += 20
                feedback.append("[+] interval_calculator.py: modulo 12 applied to interval (20/20)")
            else:
                feedback.append("[-] interval_calculator.py: missing mod-12 wrap around for intervals (0/20)")
        else:
            feedback.append("[-] interval_calculator.py could not be read")

        # ── Bug 2: chord detection enharmonic equivalence ──
        ca_content = files.get("music_theory/chord_analyzer.py", "")
        if ca_content:
            # Look at detect_chord
            detect_chord_block = ca_content.split('def detect_chord')[1].split('def detect_inversion')[0] if 'def detect_chord' in ca_content else ""
            
            # Checks if pitch_class is now being used to collect notes instead of string names
            uses_pitch_class = bool(re.search(r'pitch_class', detect_chord_block))
            buggy_name_comp = bool(re.search(r'n\.name\s*for\s*n\s*in\s*notes', detect_chord_block))
            
            if uses_pitch_class and not buggy_name_comp:
                score += 20
                feedback.append("[+] chord_analyzer.py: enharmonic equivalence fixed using pitch_class (20/20)")
            else:
                feedback.append("[-] chord_analyzer.py: still uses string comparison for chord detection (0/20)")
        else:
            feedback.append("[-] chord_analyzer.py could not be read")

        # ── Bug 3: chord inversion comparison ──────────────
        if ca_content:
            # Look at detect_inversion
            detect_inv_block = ca_content.split('def detect_inversion')[1] if 'def detect_inversion' in ca_content else ""
            
            # The fix: bass_note.pitch_class == chord.root.pitch_class
            fix_root_comp = bool(re.search(r'bass_note\.pitch_class\s*==\s*chord\.root\.pitch_class', detect_inv_block))
            buggy_type_comp = bool(re.search(r'bass_note\.name\s*==\s*chord\.chord_type', detect_inv_block))
            
            if fix_root_comp and not buggy_type_comp:
                score += 20
                feedback.append("[+] chord_analyzer.py: inversion root comparison fixed (20/20)")
            elif not buggy_type_comp and ('root' in detect_inv_block):
                # Benefit of the doubt if they wrote the logic slightly differently but removed the bug
                score += 20
                feedback.append("[+] chord_analyzer.py: inversion comparison logic corrected (20/20)")
            else:
                feedback.append("[-] chord_analyzer.py: inversion root detection remains incorrect (0/20)")

        # ── Bug 4: flat key circle of fifths ───────────────
        kd_content = files.get("music_theory/key_detector.py", "")
        if kd_content:
            # The fix: + 5 (or - 7) instead of + 7
            has_flat_direction = bool(re.search(r'\+\s*5|-\s*7', kd_content))
            buggy_sharp_direction = bool(re.search(r'current\s*\+\s*7\s*\)\s*%\s*12', kd_content))
            
            if has_flat_direction and not buggy_sharp_direction:
                score += 20
                feedback.append("[+] key_detector.py: flat key circle of fifths direction fixed (20/20)")
            else:
                feedback.append("[-] key_detector.py: still moves clockwise (+7) for flat keys (0/20)")
        else:
            feedback.append("[-] key_detector.py could not be read")

        # ── Bug 5: octave boundary during transposition ────
        tp_content = files.get("music_theory/transposer.py", "")
        if tp_content:
            # Checks if octave logic uses integer division (// 12) or modifies the old octave
            # Original code: new_octave = note.octave
            buggy_assignment = bool(re.search(r'new_octave\s*=\s*note\.octave\s*$', tp_content, re.MULTILINE))
            has_division = bool(re.search(r'//\s*12|/\s*12|divmod', tp_content))
            
            if not buggy_assignment and has_division:
                score += 20
                feedback.append("[+] transposer.py: octave boundary logic updated correctly (20/20)")
            elif not buggy_assignment and ("octave" in tp_content):
                # Partial/Full credit if they wrote custom if-else logic to fix it
                # Check pytest output to confirm if their logic actually passed the test
                if "test_octave_transposition PASSED" in test_output:
                    score += 20
                    feedback.append("[+] transposer.py: octave boundary fixed (verified by passing test) (20/20)")
                else:
                    feedback.append("[-] transposer.py: attempted fix failed transposition tests (0/20)")
            else:
                feedback.append("[-] transposer.py: still copies octave verbatim without boundary checks (0/20)")
        else:
            feedback.append("[-] transposer.py could not be read")

        # ── Cross-reference with actual test suite results ──
        if data.get("test_exit_code") == 0:
            feedback.append("\n[SUCCESS] Pytest test suite fully passes!")
        else:
            failed_tests = test_output.count("FAILED")
            feedback.append(f"\n[INFO] {failed_tests} tests are still failing in the suite.")

        # Evaluate final pass condition
        passed = score >= task_info.get("metadata", {}).get("pass_threshold", 60)

        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }
        
    finally:
        # Cleanup
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)