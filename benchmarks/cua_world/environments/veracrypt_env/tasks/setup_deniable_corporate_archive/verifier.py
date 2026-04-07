#!/usr/bin/env python3
"""
Verifier for setup_deniable_corporate_archive task.
Verifies that:
1. A hidden VeraCrypt volume container was created with correct parameters.
2. Outer volume mounts with the cover password and contains decoy files.
3. Hidden volume mounts with password + keyfile and contains sensitive files.
4. Keyfile was generated and is required for hidden volume access.
5. Verification report exists.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_setup_deniable_corporate_archive(traj, env_info, task_info):
    """
    Verify setup_deniable_corporate_archive task.
    Stub verifier - primary verification via VLM checklist.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result file."}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # 1. File Existence & Integrity (10 pts)
        if result.get('file_exists'):
            if result.get('timestamp_valid') and not result.get('is_copy'):
                score += 10
                feedback_parts.append("Container file created during task.")
            else:
                score += 3
                feedback_parts.append("Container exists but failed integrity check.")
        else:
            feedback_parts.append("Container file not found.")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # 2. Outer Volume Mountable (10 pts)
        if result.get('outer_mountable'):
            score += 10
            feedback_parts.append("Outer volume mountable with cover password.")
        else:
            feedback_parts.append("Outer volume failed to mount.")

        # 3. Outer Encryption: AES-Twofish-Serpent cascade (10 pts)
        outer_algo = result.get('outer_algo', '').lower()
        if 'aes' in outer_algo and 'twofish' in outer_algo and 'serpent' in outer_algo:
            score += 10
            feedback_parts.append(f"Outer encryption correct: {result.get('outer_algo')}")
        else:
            feedback_parts.append(f"Outer encryption incorrect: {result.get('outer_algo')}")

        # 4. Outer Hash: SHA-512 (5 pts)
        outer_hash = result.get('outer_hash', '').lower()
        if 'sha-512' in outer_hash or 'sha512' in outer_hash:
            score += 5
            feedback_parts.append("Outer hash correct: SHA-512")
        else:
            feedback_parts.append(f"Outer hash incorrect: {result.get('outer_hash')}")

        # 5. Decoy files in outer with correct checksums (10 pts)
        if result.get('outer_checksums_match') and result.get('outer_file_count', 0) >= 3:
            score += 10
            feedback_parts.append(f"All decoy files present with correct checksums.")
        elif result.get('outer_file_count', 0) > 0:
            score += 5
            feedback_parts.append(f"Some decoy files present ({result.get('outer_file_count')}).")
        else:
            feedback_parts.append("No decoy files found in outer volume.")

        # 6. Hidden Volume Mountable with password + keyfile (15 pts)
        if result.get('hidden_mountable'):
            score += 15
            feedback_parts.append("Hidden volume mountable with password + keyfile.")
        else:
            feedback_parts.append("Hidden volume failed to mount.")

        # 7. Password-only mount blocked / keyfile required (5 pts)
        if result.get('password_only_blocked'):
            score += 5
            feedback_parts.append("Keyfile requirement confirmed (password-only rejected).")
        else:
            feedback_parts.append("Warning: password-only mount was not blocked.")

        # 8. Hidden Encryption: Serpent (10 pts)
        hidden_algo = result.get('hidden_algo', '').lower()
        if 'serpent' in hidden_algo and 'aes' not in hidden_algo and 'twofish' not in hidden_algo:
            score += 10
            feedback_parts.append(f"Hidden encryption correct: {result.get('hidden_algo')}")
        elif 'serpent' in hidden_algo:
            score += 5
            feedback_parts.append(f"Hidden encryption partially correct: {result.get('hidden_algo')}")
        else:
            feedback_parts.append(f"Hidden encryption incorrect: {result.get('hidden_algo')}")

        # 9. Hidden Hash: Whirlpool (5 pts)
        hidden_hash = result.get('hidden_hash', '').lower()
        if 'whirlpool' in hidden_hash:
            score += 5
            feedback_parts.append("Hidden hash correct: Whirlpool")
        else:
            feedback_parts.append(f"Hidden hash incorrect: {result.get('hidden_hash')}")

        # 10. Sensitive files in hidden with correct checksums (10 pts)
        if result.get('hidden_checksums_match') and result.get('hidden_file_count', 0) >= 4:
            score += 10
            feedback_parts.append(f"All sensitive files present with correct checksums.")
        elif result.get('hidden_file_count', 0) > 0:
            score += 5
            feedback_parts.append(f"Some sensitive files present ({result.get('hidden_file_count')}).")
        else:
            feedback_parts.append("No sensitive files found in hidden volume.")

        # 11. Keyfile exists at correct path (5 pts)
        if result.get('keyfile_exists') and result.get('keyfile_size', 0) >= 64:
            score += 5
            feedback_parts.append("Keyfile generated at correct path.")
        else:
            feedback_parts.append("Keyfile missing or too small.")

        # 12. Verification report (5 pts)
        if result.get('report_exists'):
            score += 5
            feedback_parts.append("Verification report exists.")
        else:
            feedback_parts.append("Verification report missing.")

    except Exception as e:
        logger.error(f"Verification logic error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification logic error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Pass condition: both volumes must be mountable and score >= 70
    passed = (result.get('outer_mountable') and
              result.get('hidden_mountable') and
              score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
