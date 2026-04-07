#!/usr/bin/env python3
"""
Verifier for bess_lithium_ion_reporting task.

Scores out of 100 based on the extracted XML block from the agent's .t2s file.
Pass threshold is 75 points.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\bess_lithium_ion_result.json"

def verify_bess_lithium_ion_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)

    # 1. Retrieve the parsed results from the environment
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # 2. Check baseline constraints
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found at C:\\Tier2Data\\desert_bloom_2025_updated.t2s"}

    if not result.get("file_modified_during_task", False):
        logger.warning("File exists but was not modified during the task. Might be an old file.")

    xml = result.get("bess_chemical_xml", "")
    if not xml:
        return {"passed": False, "score": 10, "feedback": "File exported, but 'Lithium-Ion Batteries' chemical entry not found in the XML."}

    # 3. Calculate Score
    score = 10  # Base points for correctly creating the file and having the target chemical
    feedback = ["PASS: Chemical 'Lithium-Ion Batteries' found in export (+10)"]

    # Helper for case-insensitive substring search
    def has_text(text):
        return text.lower() in xml.lower()

    # --- Criteria A: Mixture & Physical State (20 points) ---
    # Look for <Mixture>true</Mixture> or <MixtureIndicator>1</MixtureIndicator>
    if re.search(r'<[^>]*Mixture[^>]*>\s*(true|1|yes)\s*<', xml, re.IGNORECASE) or has_text("Mixture"):
        score += 10
        feedback.append("PASS: Mixture flag set (+10)")
    else:
        feedback.append("FAIL: Mixture flag not found")

    if has_text("Solid"):
        score += 10
        feedback.append("PASS: Physical state 'Solid' found (+10)")
    else:
        feedback.append("FAIL: Physical state 'Solid' missing")

    # --- Criteria B: Hazards (30 points) ---
    hazards = [
        ("Flammable", 7.5),
        ("Explosive", 7.5),
        ("Acute toxicity", 7.5),
        ("target organ", 7.5)
    ]
    for kw, pts in hazards:
        if has_text(kw):
            score += pts
            feedback.append(f"PASS: Hazard containing '{kw}' found (+{pts})")
        else:
            feedback.append(f"FAIL: Hazard containing '{kw}' missing")

    # --- Criteria C: Quantities (20 points) ---
    if "2500000" in xml:
        score += 10
        feedback.append("PASS: Target quantity 2,500,000 found (+10)")
    else:
        feedback.append("FAIL: Target quantity 2,500,000 missing")

    if "365" in xml:
        score += 10
        feedback.append("PASS: 365 days on site (+10)")
    else:
        feedback.append("FAIL: 365 days on site missing")

    # --- Criteria D: Storage (20 points) ---
    if has_text("BESS Pads"):
        score += 10
        feedback.append("PASS: Storage location description 'BESS Pads...' found (+10)")
    else:
        feedback.append("FAIL: Storage location description missing")

    if has_text("Ambient"):
        score += 10
        feedback.append("PASS: Storage condition 'Ambient' found (+10)")
    else:
        feedback.append("FAIL: Storage condition 'Ambient' missing")

    # 4. Final Evaluation
    score = min(int(score), 100)
    passed = score >= metadata.get("pass_threshold", 75)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }