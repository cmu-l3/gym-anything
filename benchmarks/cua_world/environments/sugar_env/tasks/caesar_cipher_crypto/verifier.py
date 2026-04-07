#!/usr/bin/env python3
"""
Verifier for caesar_cipher_crypto task.

Checks that:
1. The target directory was created.
2. caesar_cipher.py exists, is reasonably sized, and contains python function constructs.
3. encrypted.txt exists and exactly matches the expected Caesar cipher output.
4. decrypted.txt exists and exactly matches the original plaintext.
5. report.txt exists and contains the required summary information.
All files must have been created/modified after the task started.
"""

import json
import os
import tempfile
import re


def verify_caesar_cipher(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_plaintext = metadata.get('expected_plaintext', '').strip()
    expected_ciphertext = metadata.get('expected_ciphertext', '').strip()

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/caesar_cipher_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    files = result.get("files", {})

    # Criterion 1: Output directory exists (5 pts)
    if result.get("crypto_dir_exists"):
        score += 5
        feedback.append("Directory /crypto/ exists")
    else:
        feedback.append("Directory /crypto/ not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Check caesar_cipher.py (20 pts total)
    py_info = files.get("caesar_cipher.py", {})
    if py_info.get("exists") and py_info.get("created_during_task"):
        py_content = py_info.get("content", "")
        if py_info.get("size", 0) > 200:
            score += 10
            feedback.append("caesar_cipher.py has reasonable size")
        else:
            feedback.append("caesar_cipher.py exists but is too small (likely a stub)")
        
        if "def " in py_content:
            score += 5
            feedback.append("Code contains function definition")
            
        if "chr" in py_content or "ord" in py_content or "maketrans" in py_content:
            score += 5
            feedback.append("Code contains character manipulation logic")
    else:
        feedback.append("caesar_cipher.py missing or not created during task")

    # Check encrypted.txt (30 pts total)
    enc_info = files.get("encrypted.txt", {})
    encrypted_matched = False
    if enc_info.get("exists") and enc_info.get("created_during_task"):
        score += 5
        enc_content = enc_info.get("content", "").strip()
        
        if enc_content == expected_ciphertext:
            score += 25
            encrypted_matched = True
            feedback.append("encrypted.txt matches expected ciphertext exactly")
        else:
            # Partial credit if mostly correct (e.g. wrong casing, but right shift)
            correct_chars = sum(1 for a, b in zip(enc_content, expected_ciphertext) if a == b)
            if len(expected_ciphertext) > 0 and (correct_chars / len(expected_ciphertext)) > 0.8:
                score += 10
                feedback.append("encrypted.txt partially matches expected ciphertext")
            else:
                feedback.append("encrypted.txt content is incorrect")
    else:
        feedback.append("encrypted.txt missing or not created during task")

    # Check decrypted.txt (25 pts total)
    dec_info = files.get("decrypted.txt", {})
    decrypted_matched = False
    if dec_info.get("exists") and dec_info.get("created_during_task"):
        score += 5
        dec_content = dec_info.get("content", "").strip()
        
        if dec_content == expected_plaintext:
            score += 20
            decrypted_matched = True
            feedback.append("decrypted.txt matches original plaintext exactly")
        else:
            feedback.append("decrypted.txt content does not match plaintext")
    else:
        feedback.append("decrypted.txt missing or not created during task")

    # Check report.txt (20 pts total)
    rep_info = files.get("report.txt", {})
    if rep_info.get("exists") and rep_info.get("created_during_task"):
        if rep_info.get("size", 0) > 100:
            score += 5
            feedback.append("report.txt created with sufficient content")
        
        rep_content = rep_info.get("content", "")
        if "7" in rep_content:
            score += 5
            feedback.append("report.txt contains shift value '7'")
            
        # Check if both plaintext and ciphertext segments appear in the report
        has_pt = expected_plaintext[:20] in rep_content
        has_ct = expected_ciphertext[:20] in rep_content
        if has_pt and has_ct:
            score += 10
            feedback.append("report.txt contains both plaintext and ciphertext references")
        else:
            feedback.append("report.txt missing plaintext or ciphertext references")
    else:
        feedback.append("report.txt missing or not created during task")

    # Final scoring calculations
    score = min(score, 100)
    
    # Pass threshold: >=65 and both core crypto text files must be exactly correct.
    passed = score >= 65 and encrypted_matched and decrypted_matched

    if passed:
        feedback.append("SUCCESS: Caesar cipher correctly implemented and verified.")
    else:
        feedback.insert(0, "FAILED: ")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }