#!/usr/bin/env python3
"""
Verifier for offer_letter_batch task.

An HR Manager must create 5 personalized employment offer letters for
new hires at Crestline Medical Devices, Inc., using hire data from a JSON
reference file. Each letter must be a complete professional document
containing the hire's specific name, title, salary, and start date.

Scoring (100 points):
  - Letters found (each of 5 = 10 pts each):            up to 50 pts
  - Letters with correct hire-specific content (each):   up to 30 pts
  - Letters substantial in size (each ≥ 2KB):            up to 20 pts

Per-letter scoring (20 pts max each):
  - File exists:                       10 pts
  - Correct content (name+title+salary): 6 pts
  - Substantial size (≥ 2KB):           4 pts

Pass threshold: 70 points (requires at least 4 good letters, or all 5 with minor gaps)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

EXPECTED_FILES = [
    "offer_letter_Okonkwo_Amara.odt",
    "offer_letter_Tremblay_Kevin.odt",
    "offer_letter_Nair_Preethi.odt",
    "offer_letter_Vasquez_Jordan.odt",
    "offer_letter_Petrov_Marcus.odt"
]


def verify_offer_letter_batch(traj, env_info, task_info):
    """Verify all 5 offer letters were properly created."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy/parse error: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    # ── GATE: at least one file must exist ────────────────────────────────
    letters_found = result.get('letters_found', 0)
    if letters_found == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No offer letter files found in /home/ga/Documents/. Expected 5 .odt files."
        }

    score = 0
    feedback_parts = []
    subscores = {}
    letters_data = result.get('letters', {})

    # ── Per-letter scoring (20 pts each, 5 letters = 100 pts max) ─────────
    for fname in EXPECTED_FILES:
        hire_name = fname.replace("offer_letter_", "").replace(".odt", "").replace("_", " ")
        letter = letters_data.get(fname, {})
        letter_score = 0

        try:
            if letter.get('exists'):
                letter_score += 10
                if letter.get('is_substantial'):
                    letter_score += 4
                if letter.get('has_correct_content'):
                    letter_score += 6
            score += letter_score
            subscores[fname] = letter_score
            feedback_parts.append(
                f"{hire_name}: {letter_score}/20 pts "
                f"(exists={letter.get('exists', False)}, "
                f"content={letter.get('has_correct_content', False)}, "
                f"size={letter.get('file_size', 0)}B)"
            )
        except Exception as e:
            feedback_parts.append(f"{hire_name}: check error: {e}")

    # ── Pass determination ────────────────────────────────────────────────
    # 70 pts = 3 letters with full 20pts + some partial credit elsewhere,
    # or 4 letters with file exists (40) + substantial (16) + content (24) = impossible with 4 letters full
    # Actually 70 pts needs nearly 4 full letters (4 * 20 = 80) or 5 letters partial
    # Realistic: 4 letters with exists(10)+content(6)+size(4) = 80 pts passes
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria evaluated",
        "subscores": subscores,
        "details": {
            "letters_found": letters_found,
            "letters_substantial": result.get('letters_substantial', 0),
            "letters_with_correct_content": result.get('letters_with_correct_content', 0),
        }
    }
