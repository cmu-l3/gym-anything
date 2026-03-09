#!/usr/bin/env python3
"""Verifier for fix_file_encoding_issues task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_file_encoding_issues(traj, env_info, task_info):
    """
    Verify the file encoding fix.
    
    Criteria:
    1. File is valid UTF-8 (20 pts)
    2. File content has correct symbols (€, £, ¥) (30 pts)
    3. File has LF line endings (not CRLF) (20 pts)
    4. Project encoding is set to UTF-8 in .idea/encodings.xml (10 pts)
    5. Maven tests pass (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_json.close()
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    score = 0
    feedback_parts = []
    
    # 1 & 2 & 3: Analyze the target file content
    remote_file_path = result.get("target_file_path")
    file_content_bytes = b""
    
    if remote_file_path:
        try:
            tmp_java = tempfile.NamedTemporaryFile(delete=False, suffix='.java')
            tmp_java.close()
            copy_from_env(remote_file_path, tmp_java.name)
            with open(tmp_java.name, 'rb') as f:
                file_content_bytes = f.read()
            os.unlink(tmp_java.name)
        except Exception as e:
            feedback_parts.append(f"Failed to read result file: {e}")

    # Check 1: Valid UTF-8 (20 pts)
    is_utf8 = False
    try:
        file_content_str = file_content_bytes.decode('utf-8')
        is_utf8 = True
        score += 20
        feedback_parts.append("File is valid UTF-8")
    except UnicodeDecodeError:
        feedback_parts.append("File is NOT valid UTF-8 (encoding check failed)")
        # Try to decode with 1252 just to see what's in there for debugging feedback
        try:
            debug_str = file_content_bytes.decode('cp1252')
            if "€" in debug_str:
                feedback_parts.append("File is still encoded in Windows-1252")
        except:
            pass
        file_content_str = "" # Cannot proceed with content check if decode failed

    # Check 2: Correct Symbols (30 pts)
    expected_symbols = ["€", "£", "¥"]
    missing_symbols = []
    if is_utf8:
        for sym in expected_symbols:
            if sym not in file_content_str:
                missing_symbols.append(sym)
        
        if not missing_symbols:
            score += 30
            feedback_parts.append("All currency symbols preserved correctly")
        else:
            feedback_parts.append(f"Missing symbols: {', '.join(missing_symbols)}")
            # Check for common mojibake
            if "â‚¬" in file_content_str:
                feedback_parts.append("Found mojibake (â‚¬) - Double-converted?")
            if "\ufffd" in file_content_str: # Replacement char
                feedback_parts.append("Found replacement chars () - Data lost during conversion")

    # Check 3: Line Endings (20 pts)
    if is_utf8:
        if b'\r\n' in file_content_bytes:
            feedback_parts.append("File still has CRLF (Windows) line endings")
        elif b'\n' in file_content_bytes:
            score += 20
            feedback_parts.append("Line endings converted to LF (Unix)")
        else:
            # Single line file or empty?
            if len(file_content_bytes) > 0:
                score += 20 # Acceptable if no CRLF found
                feedback_parts.append("No CRLF found")

    # Check 4: Project Settings (10 pts)
    enc_xml = result.get("project_encoding_xml", "")
    if enc_xml and ('charset="UTF-8"' in enc_xml or "UTF-8" in enc_xml):
        score += 10
        feedback_parts.append("Project encoding configured to UTF-8")
    else:
        feedback_parts.append("Project encoding settings not updated in .idea/encodings.xml")

    # Check 5: Tests Pass (20 pts)
    if result.get("test_result") == "pass":
        score += 20
        feedback_parts.append("Unit tests passed")
    else:
        feedback_parts.append("Unit tests failed")

    passed = score >= 70 and is_utf8 and not missing_symbols

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }