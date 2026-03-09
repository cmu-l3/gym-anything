#!/usr/bin/env python3
"""
Verifier for customize_accessibility_profile task.

Scoring breakdown (100 pts total):
  - letter.talon-list has all 26 NATO phonetics correct:   50 pts
    (2 pts per correct letter, up to 26 = 52, capped at 50)
  - letter.talon-list preserves list header 'user.letter': 10 pts
  - user.medical_terms.talon-list created with >= 8 terms: 25 pts
  - medical list has correct talon-list header format:     15 pts
  Pass threshold: 60 pts.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

NATO_ALPHABET = {
    'a': 'alpha',    'b': 'bravo',    'c': 'charlie', 'd': 'delta',
    'e': 'echo',     'f': 'foxtrot',  'g': 'golf',    'h': 'hotel',
    'i': 'india',    'j': 'juliett',  'k': 'kilo',    'l': 'lima',
    'm': 'mike',     'n': 'november', 'o': 'oscar',   'p': 'papa',
    'q': 'quebec',   'r': 'romeo',    's': 'sierra',  't': 'tango',
    'u': 'uniform',  'v': 'victor',   'w': 'whiskey', 'x': 'x-ray',
    'y': 'yankee',   'z': 'zulu',
}

# Accept common NATO spelling variants
NATO_VARIANTS = {
    'juliet': 'j',   # common alternative to juliett
    'x ray': 'x',   # alternative to x-ray
    'xray': 'x',
}

REQUIRED_MEDICAL_TERMS = ['stat', 'prn', 'bid', 'tid', 'qid', 'npo', 'icu', 'ppe']


def _parse_talon_list_entries(content):
    """Parse key: value pairs from a .talon-list file body (after the '-' separator)."""
    entries = {}
    lines = content.splitlines()
    in_body = False
    for line in lines:
        stripped = line.strip()
        if stripped == '-':
            in_body = True
            continue
        if not in_body or not stripped or stripped.startswith('#'):
            continue
        if ':' in stripped:
            parts = stripped.split(':', 1)
            key = parts[0].strip().lower()
            val = parts[1].strip().lower()
            entries[key] = val
    return entries


def _get_list_header(content):
    """Return the list: header name from a .talon-list file."""
    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith('list:'):
            return stripped[5:].strip()
    return ''


def verify_customize_accessibility_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata    = task_info.get('metadata', {})
    result_path = metadata.get('result_file',
                               'C:\\Users\\Docker\\customize_accessibility_profile_result.json')
    min_medical = metadata.get('min_medical_terms', 8)

    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp.close()
    try:
        copy_from_env(result_path, temp.name)
        with open(temp.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.ps1 may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        try:
            os.unlink(temp.name)
        except OSError:
            pass

    score = 0
    feedback_parts = []

    letter_content  = result.get('letter_content', '').replace('\\n', '\n').replace('\\t', '\t')
    medical_content = result.get('medical_content', '').replace('\\n', '\n').replace('\\t', '\t')
    letter_exists   = result.get('letter_file_exists', False)
    medical_exists  = result.get('medical_file_exists', False)

    # ------------------------------------------------------------------
    # Criterion 1: letter.talon-list preserves 'user.letter' header (10 pts)
    # ------------------------------------------------------------------
    if not letter_exists or not letter_content.strip():
        feedback_parts.append("FAIL C1: letter.talon-list not found or empty")
    else:
        header = _get_list_header(letter_content)
        if header == 'user.letter':
            score += 10
            feedback_parts.append("PASS C1: letter.talon-list has correct 'user.letter' header")
        else:
            feedback_parts.append(f"FAIL C1: letter.talon-list header is '{header}' (expected 'user.letter')")

    # ------------------------------------------------------------------
    # Criterion 2: NATO phonetics — up to 50 pts (2 pts per correct entry)
    # ------------------------------------------------------------------
    if letter_content.strip():
        entries = _parse_talon_list_entries(letter_content)
        correct_count = 0
        wrong_letters = []
        for letter, nato_word in NATO_ALPHABET.items():
            # The key in the list should be the NATO word, value should be the letter
            # i.e. "alpha: a"  (the voice trigger is "alpha", the output is "a")
            found = False
            for key, val in entries.items():
                key_norm = key.lower().strip()
                val_norm = val.lower().strip()
                # Accept NATO word as key mapping to letter
                if val_norm == letter and (key_norm == nato_word
                                           or key_norm in NATO_VARIANTS
                                           and NATO_VARIANTS[key_norm] == letter):
                    found = True
                    break
                # Also accept letter as key mapping to NATO word (alternative format)
                if key_norm == letter and val_norm == nato_word:
                    found = True
                    break
            if found:
                correct_count += 1
            else:
                wrong_letters.append(letter)

        nato_score = min(50, correct_count * 2)
        score += nato_score
        if correct_count == 26:
            feedback_parts.append("PASS C2: All 26 NATO phonetics correct")
        elif correct_count >= 20:
            feedback_parts.append(f"PARTIAL C2: {correct_count}/26 NATO phonetics correct "
                                   f"(missing: {', '.join(wrong_letters[:6])}{'...' if len(wrong_letters) > 6 else ''})")
        else:
            feedback_parts.append(f"FAIL C2: only {correct_count}/26 NATO phonetics correct "
                                   f"(missing: {', '.join(wrong_letters[:8])})")
        logger.info(f"NATO correct: {correct_count}/26, score contribution: {nato_score}")
    else:
        feedback_parts.append("FAIL C2: letter.talon-list is empty")

    # ------------------------------------------------------------------
    # Criterion 3: medical_terms list created with correct header (15 pts)
    # ------------------------------------------------------------------
    if not medical_exists or not medical_content.strip():
        feedback_parts.append("FAIL C3: user.medical_terms.talon-list not created")
    else:
        med_header = _get_list_header(medical_content)
        if med_header == 'user.medical_terms':
            score += 15
            feedback_parts.append("PASS C3: medical list has correct 'user.medical_terms' header")
        elif med_header:
            score += 5
            feedback_parts.append(f"PARTIAL C3: medical list header is '{med_header}' "
                                   "(expected 'user.medical_terms')")
        else:
            feedback_parts.append("FAIL C3: medical list missing 'list:' header")

    # ------------------------------------------------------------------
    # Criterion 4: >= 8 medical terms in the list (25 pts)
    # ------------------------------------------------------------------
    if medical_content.strip():
        med_entries = _parse_talon_list_entries(medical_content)
        # Count entries where keys or values are recognized medical abbreviations
        all_terms = set(list(med_entries.keys()) + list(med_entries.values()))
        found_required = [t for t in REQUIRED_MEDICAL_TERMS if t.lower() in all_terms]
        total_entries = len(med_entries)

        if total_entries >= min_medical:
            score += 25
            feedback_parts.append(f"PASS C4: {total_entries} medical terms in list "
                                   f"({len(found_required)} required terms found: "
                                   f"{', '.join(found_required)})")
        elif total_entries >= 4:
            score += 12
            feedback_parts.append(f"PARTIAL C4: only {total_entries} medical terms "
                                   f"({min_medical} required)")
        else:
            feedback_parts.append(f"FAIL C4: only {total_entries} medical terms "
                                   f"({min_medical} required)")
    else:
        feedback_parts.append("FAIL C4: user.medical_terms.talon-list is empty")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
