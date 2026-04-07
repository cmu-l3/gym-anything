#!/usr/bin/env python3
"""
Verifier for the debug_wad_asset_extractor task.

Checks whether the agent identified and fixed 5 binary parsing bugs:
1. Endianness (>I to <I)
2. Seeking (offset, 1 to offset, 0)
3. String decoding (name_bytes.index(b'\x00') to .rstrip or .split)
4. Marker Lumps (skip size == 0)
5. RGB Ordering (b, g, r = ... to r, g, b = ...)

Uses AST / Regex analysis on exported code files to robustly grade fixes,
and also uses VLM to verify trajectory activity.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wad_extractor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/wad_extractor_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    files = result_data.get('files', {})
    score = 0
    feedback = []
    
    # ── Bug 1: Endianness in wad_parser.py ─────────────────────────
    parser_src = files.get("wad_parser.py", "")
    if "ERROR:" in parser_src or not parser_src:
        feedback.append("[-] wad_parser.py missing or unreadable")
    else:
        # Looking for Little Endian format '<4sII' or just '<I'
        has_big_endian = "'>4sII'" in parser_src or "'>I'" in parser_src
        has_little_endian = "'<4sII'" in parser_src or "'<I'" in parser_src
        
        if has_little_endian and not has_big_endian:
            score += 20
            feedback.append("[+] Endianness fixed (using Little-Endian unpack) [20/20]")
        elif not has_big_endian and re.search(r'unpack\([^>]+', parser_src):
            # Might be constructed dynamically or uses default native
            score += 15
            feedback.append("[~] Endianness altered, > removed [15/20]")
        else:
            feedback.append("[-] Endianness unfixed (still uses Big-Endian >) [0/20]")

    # ── Bug 2: Absolute Seeking in wad_parser.py ───────────────────
    if not parser_src:
        pass # Already warned
    else:
        # Looking for `f.seek(offset)` or `f.seek(offset, 0)` replacing `f.seek(offset, 1)`
        has_relative = re.search(r'f\.seek\(\s*[^,]+,\s*1\s*\)', parser_src)
        has_absolute = re.search(r'f\.seek\(\s*[^,]+(?:,\s*0)?\s*\)', parser_src)
        
        if has_absolute and not has_relative:
            score += 20
            feedback.append("[+] Seeking fixed (uses absolute file offsets) [20/20]")
        else:
            feedback.append("[-] Seeking unfixed (still uses relative seek 1) [0/20]")

    # ── Bug 3: String Decoding in wad_parser.py ────────────────────
    if not parser_src:
        pass
    else:
        # Looking for removal of `.index(b'\x00')` which throws ValueError
        has_buggy_index = "index(b'\\x00')" in parser_src
        has_safe_split = "split(b'\\x00')" in parser_src
        has_safe_strip = "rstrip(b'\\x00')" in parser_src or "rstrip('\\x00')" in parser_src
        has_safe_replace = "replace(b'\\x00'" in parser_src
        
        if not has_buggy_index and (has_safe_split or has_safe_strip or has_safe_replace):
            score += 20
            feedback.append("[+] String decoding fixed (handles 8-char names without nulls) [20/20]")
        elif not has_buggy_index:
            score += 10
            feedback.append("[~] Buggy index call removed, but standard replace not found [10/20]")
        else:
            feedback.append("[-] String decoding unfixed (still uses hard index) [0/20]")

    # ── Bug 4: Marker Lumps in extractor.py ────────────────────────
    ext_src = files.get("extractor.py", "")
    if "ERROR:" in ext_src or not ext_src:
        feedback.append("[-] extractor.py missing or unreadable")
    else:
        # Looking for a check to skip size 0 (e.g. `if lump['size'] == 0: continue`)
        # Accept it in either extractor.py or wad_parser.py
        size_check_ext = re.search(r'if\s+[^:]*size[^:]*==\s*0\s*:|if\s+not\s+[^:]*size\s*:', ext_src)
        size_check_prs = re.search(r'if\s+[^:]*size[^:]*==\s*0\s*:|if\s+not\s+[^:]*size\s*:', parser_src)
        
        if size_check_ext or size_check_prs:
            score += 20
            feedback.append("[+] Marker lumps handled (skips 0-byte lumps) [20/20]")
        else:
            feedback.append("[-] Marker lumps unfixed (does not skip size==0) [0/20]")

    # ── Bug 5: RGB Ordering in playpal_converter.py ────────────────
    pp_src = files.get("playpal_converter.py", "")
    if "ERROR:" in pp_src or not pp_src:
        feedback.append("[-] playpal_converter.py missing or unreadable")
    else:
        # Original: b = p[i]; g = p[i+1]; r = p[i+2]
        # Fixed: r = p[i]; g = p[i+1]; b = p[i+2]
        
        # We can look for `r\s*=\s*palette_data\[i\]`
        r_correct = re.search(r'r\s*=\s*palette_data\[\s*i\s*\]', pp_src)
        b_correct = re.search(r'b\s*=\s*palette_data\[\s*i\s*\+\s*2\s*\]', pp_src)
        
        # Or maybe they just packed them directly: `colors.append((palette_data[i], ...))`
        direct_append = re.search(r'colors\.append\(\s*\(\s*palette_data\[\s*i\s*\]', pp_src)
        
        if (r_correct and b_correct) or direct_append:
            score += 20
            feedback.append("[+] RGB ordering fixed (reads sequential R, G, B) [20/20]")
        else:
            feedback.append("[-] RGB ordering unfixed (still reads B, G, R) [0/20]")

    # ── VLM Verification (Trajectory checking) ─────────────────────
    vlm_points = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=3)
            
            if frames:
                prompt = (
                    "You are verifying a coding task in VS Code. "
                    "Did the user actively edit Python files and attempt to run the extraction script? "
                    "Look for evidence of editing code files (wad_parser.py, extractor.py, playpal_converter.py) "
                    "and terminal output indicating script execution. "
                    "Respond with a JSON object: {\"actively_worked\": true/false}"
                )
                
                vlm_result = query_vlm(prompt=prompt, images=frames)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("actively_worked", False):
                        vlm_points = 10
                        feedback.append("[+] VLM verified trajectory coding activity")
                    else:
                        feedback.append("[-] VLM did not observe active coding work")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    # Pass condition
    # Requires at least 60 static analysis points (3/5 bugs). VLM is bonus/anti-gaming context.
    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score + vlm_points, 100),
        "feedback": "\n".join(feedback)
    }