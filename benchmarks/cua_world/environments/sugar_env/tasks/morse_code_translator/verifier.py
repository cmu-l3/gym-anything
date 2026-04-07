#!/usr/bin/env python3
"""
Verifier for the morse_code_translator task.
Checks file presence, script execution logic, adherence to ITU standards,
and tests resilience against hardcoded outputs (gaming).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Standard ITU Morse Code mappings
MORSE_STD = {
    'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.', 'F': '..-.',
    'G': '--.', 'H': '....', 'I': '..', 'J': '.---', 'K': '-.-', 'L': '.-..',
    'M': '--', 'N': '-.', 'O': '---', 'P': '.--.', 'Q': '--.-', 'R': '.-.',
    'S': '...', 'T': '-', 'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-',
    'Y': '-.--', 'Z': '--..',
    '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
    '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.'
}

def normalize_morse(s):
    """Normalize morse string spacing to gracefully handle variation."""
    if not s:
        return ""
    # Normalize slashes to standard " / "
    s = re.sub(r'\s*/\s*', ' / ', s)
    # Remove extra internal spaces
    s = re.sub(r'\s+', ' ', s)
    return s.strip()

def extract_mappings(content):
    """Extract mappings from reference file format 'A .-'."""
    mappings = {}
    for line in content.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2:
            char = parts[0].upper()
            code = parts[1]
            if char in MORSE_STD:
                mappings[char] = code
    return mappings

def verify_morse_code_translator(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_encoded = metadata.get('expected_encoded', "... ..- --. .- .-. / .-.. .- -... ...")
    expected_decoded = metadata.get('expected_decoded', "SOS")
    expected_roundtrip = metadata.get('expected_roundtrip', "HELLO WORLD")
    novel_encode_expected = metadata.get('novel_encode_output', "- . ... -")
    novel_decode_expected = metadata.get('novel_decode_output', "CODE")

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Anti-gaming check: File timing
    if not result.get("files_created_after_start", False):
        feedback.append("WARNING: Files not created during task window (possible caching).")

    # 1. Directory exists (3 pts)
    if result.get("dir_exists"):
        score += 3
        feedback.append("Directory exists (+3)")
    else:
        feedback.append("Directory /home/ga/Documents/morse missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Reference file exists & valid (5 pts + 12 pts for letters + 5 pts for digits)
    ref_content = result.get("reference_content", "")
    if result.get("reference_exists") and result.get("reference_size", 0) > 100:
        score += 5
        feedback.append("Reference file valid size (+5)")
        
        parsed_mappings = extract_mappings(ref_content)
        
        # Check letters
        letters_correct = sum(1 for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" if parsed_mappings.get(c) == MORSE_STD[c])
        if letters_correct == 26:
            score += 12
            feedback.append("All 26 letters mapped correctly (+12)")
        else:
            partial = int(12 * (letters_correct / 26))
            score += partial
            feedback.append(f"{letters_correct}/26 letters mapped correctly (+{partial})")

        # Check digits
        digits_correct = sum(1 for c in "0123456789" if parsed_mappings.get(c) == MORSE_STD[c])
        if digits_correct == 10:
            score += 5
            feedback.append("All 10 digits mapped correctly (+5)")
        else:
            partial = int(5 * (digits_correct / 10))
            score += partial
            feedback.append(f"{digits_correct}/10 digits mapped correctly (+{partial})")
    else:
        feedback.append("Reference file missing or too small")

    # 3. encode.sh exists, executable, and non-trivial (5 + 2 pts)
    if result.get("encode_exists"):
        if result.get("encode_executable"):
            score += 5
            feedback.append("encode.sh executable (+5)")
        if result.get("encode_size", 0) > 100:
            score += 2
            feedback.append("encode.sh non-trivial size (+2)")
    
    # 4. decode.sh exists, executable, and non-trivial (5 + 2 pts)
    if result.get("decode_exists"):
        if result.get("decode_executable"):
            score += 5
            feedback.append("decode.sh executable (+5)")
        if result.get("decode_size", 0) > 100:
            score += 2
            feedback.append("decode.sh non-trivial size (+2)")

    # 5. Core functionality outputs
    enc_out = normalize_morse(result.get("encoded_output_content", ""))
    if enc_out == expected_encoded:
        score += 18
        feedback.append("Encoded 'SUGAR LABS' correctly (+18)")
    else:
        feedback.append(f"Encoded output mismatch. Expected '{expected_encoded}', got '{enc_out}'")

    dec_out = result.get("decoded_output_content", "").strip().upper()
    if dec_out == expected_decoded:
        score += 13
        feedback.append("Decoded 'SOS' correctly (+13)")
    else:
        feedback.append(f"Decoded output mismatch. Expected '{expected_decoded}', got '{dec_out}'")

    rt_out = result.get("roundtrip_output_content", "").strip().upper()
    if rt_out == expected_roundtrip:
        score += 15
        feedback.append("Roundtrip 'HELLO WORLD' correct (+15)")
    else:
        feedback.append("Roundtrip output mismatch")

    # 6. Generalization / Anti-gaming (Novel tests)
    novel_enc = normalize_morse(result.get("novel_encode_output", ""))
    novel_enc_correct = (novel_enc == novel_encode_expected)
    if novel_enc_correct:
        score += 8
        feedback.append("Generalization encode check passed (+8)")

    novel_dec = result.get("novel_decode_output", "").strip().upper()
    novel_dec_correct = (novel_dec == novel_decode_expected)
    if novel_dec_correct:
        score += 7
        feedback.append("Generalization decode check passed (+7)")

    # Anti-gaming penalty: If scripts work on static files but fail generalization
    if (enc_out == expected_encoded and not novel_enc_correct) or \
       (dec_out == expected_decoded and not novel_dec_correct):
        score -= 15
        feedback.append("PENALTY: Scripts appear hardcoded to test cases (-15)")

    score = max(0, min(100, score))
    
    passed = (score >= 65 and 
              enc_out == expected_encoded and 
              dec_out == expected_decoded and 
              (letters_correct + digits_correct) >= 30)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "reference_valid": (letters_correct + digits_correct) >= 30,
            "encoded_correct": (enc_out == expected_encoded),
            "decoded_correct": (dec_out == expected_decoded),
            "generalization_passed": (novel_enc_correct and novel_dec_correct)
        }
    }