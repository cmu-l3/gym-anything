#!/usr/bin/env python3
"""
Verifier for iat_counterbalanced_debug task.

Background: The Implicit Association Test (IAT) is a standardized paradigm for measuring
implicit attitudes (Greenwald, McGhee & Schwartz, 1998). The critical feature of the IAT
is that blocks 3 (compatible mapping) and 4 (incompatible mapping) must appear in a specific
counterbalanced order to produce the D-score effect size metric. A broken IAT yields invalid
results and cannot be published.

The broken experiment has 5 planted bugs + 1 missing required element:
  BUG 1: Block 4 (incompatible) appears BEFORE Block 3 (compatible) in the Flow
  BUG 2: Block 2 (practice) loop has nReps = 0 (participants never see practice trials)
  BUG 3: Code component in b3_trial uses = instead of == (Python syntax/logic error)
  BUG 4: b2_label text component color references '$category_color' (column doesn't exist; should be '$stim_color')
  BUG 5: Data filename in Settings uses 'participant' as a literal string (not $participant variable)
  MISSING: No 'debrief' routine at end of the experiment Flow

Scoring (100 points):
  1. File exists, valid XML, modified after task start (10 pts)
  2. BUG 1 fixed: Block 3 (compatible) before Block 4 (incompatible) in Flow (20 pts)
  3. BUG 2 fixed: Block 2 practice loop nReps > 0 (15 pts)
  4. BUG 3 fixed: Code component uses == for comparison (15 pts)
  5. BUG 4 fixed: b2_label color references '$stim_color' or equivalent (15 pts)
  6. BUG 5 fixed: Data filename references participant variable correctly (10 pts)
  7. DEBRIEF routine added at end of flow (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/iat_counterbalanced_debug_result.json"


def _parse_iat_psyexp(filepath):
    """Independently parse the fixed IAT .psyexp."""
    import xml.etree.ElementTree as ET

    data = {
        "is_valid_xml": False,
        "bug1_flow_order_fixed": False,
        "bug2_practice_nreps_fixed": False,
        "bug3_code_equals_fixed": False,
        "bug4_color_ref_fixed": False,
        "bug5_filename_fixed": False,
        "has_debrief_routine": False,
        "flow_order": [],
        "b2_label_color_value": "",
        "code_each_frame": "",
        "data_filename_value": "",
        "param_count": 0,
        "line_count": 0,
    }

    try:
        with open(filepath) as f:
            data["line_count"] = sum(1 for _ in f)

        tree = ET.parse(filepath)
        root = tree.getroot()

        if "PsychoPy" in root.tag or "PsychoPy" in str(root.attrib):
            data["is_valid_xml"] = True

        data["param_count"] = len(root.findall(".//*[@name]"))

        # Bug 5: Settings → Data filename
        settings = root.find("Settings") or root.find(".//Settings")
        if settings is not None:
            for param in settings:
                if param.get("name") == "Data filename":
                    val = param.get("val", "")
                    data["data_filename_value"] = val
                    if "participant" in val and (
                        "expInfo['participant']" in val
                        or 'expInfo["participant"]' in val
                        or "$participant" in val
                    ):
                        data["bug5_filename_fixed"] = True

        # Routines
        routines = root.find("Routines") or root.find(".//Routines")
        if routines is not None:
            for routine in routines:
                rname = routine.get("name", routine.tag)
                rl = rname.lower()

                if "debrief" in rl:
                    data["has_debrief_routine"] = True

                # Bug 4: b2_trial label color
                if rname == "b2_trial":
                    for comp in routine:
                        if "label" in comp.get("name", "").lower():
                            for param in comp:
                                if param.get("name") == "color":
                                    val = param.get("val", "")
                                    data["b2_label_color_value"] = val
                                    if "stim_color" in val.lower():
                                        data["bug4_color_ref_fixed"] = True

                # Bug 3: code component in b3_trial
                if rname == "b3_trial":
                    for comp in routine:
                        if "Code" in comp.tag or "code" in comp.get("name", "").lower():
                            for param in comp:
                                if param.get("name") == "Each Frame":
                                    code = param.get("val", "")
                                    data["code_each_frame"] = code[:300]
                                    # Fixed: if comparison uses == not =
                                    if re.search(r"if\s+\w[\w.]*\s*==\s*0", code):
                                        data["bug3_code_equals_fixed"] = True

        # Flow order analysis
        flow = root.find("Flow") or root.find(".//Flow")
        if flow is not None:
            flow_items = []
            for elem in flow:
                if elem.tag == "Routine":
                    flow_items.append(("routine", elem.get("name", "")))
                elif "LoopInitiator" in elem.tag:
                    lname = elem.get("name", "")
                    nreps = ""
                    for param in elem:
                        pn = param.get("name", "")
                        pv = param.get("val", "")
                        if pn == "nReps":
                            nreps = pv
                    flow_items.append(("loop", lname, nreps))

            data["flow_order"] = [item[1] for item in flow_items]

            # Bug 2: block2 loop nReps
            for item in flow_items:
                if item[0] == "loop" and "block2" in item[1].lower():
                    try:
                        if float(item[2]) > 0:
                            data["bug2_practice_nreps_fixed"] = True
                    except Exception:
                        pass

            # Bug 1: block3 (compatible) must come before block4 (incompatible)
            b3_pos = -1
            b4_pos = -1
            for i, item in enumerate(flow_items):
                if item[0] == "loop":
                    nl = item[1].lower()
                    if ("block3" in nl or "compatible" in nl) and "incompat" not in nl and b3_pos < 0:
                        b3_pos = i
                    if ("block4" in nl or "incompatible" in nl) and b4_pos < 0:
                        b4_pos = i

            if b3_pos >= 0 and b4_pos >= 0 and b3_pos < b4_pos:
                data["bug1_flow_order_fixed"] = True

    except Exception as e:
        logger.warning(f"IAT parse error: {e}")

    return data


def verify_iat_counterbalanced_debug(traj, env_info, task_info):
    """
    Verify the IAT counterbalanced debug task.

    Checks that all 5 bugs are fixed and the debrief routine is added.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Step 1: Copy and parse export JSON ---
    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    # --- Step 2: Independent re-parse of the output file ---
    independent = {}
    output_path = task_info.get("metadata", {}).get("output_file",
                                                     "/home/ga/PsychoPyExperiments/iat_fixed.psyexp")
    tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix=".psyexp")
    tmp2.close()
    try:
        copy_from_env(output_path, tmp2.name)
        independent = _parse_iat_psyexp(tmp2.name)
    except Exception as e:
        logger.warning(f"Independent parse failed: {e}")
    finally:
        try:
            os.unlink(tmp2.name)
        except Exception:
            pass

    # --- Criterion 1: File exists, valid XML, modified after task start (10 pts) ---
    file_exists = result.get("file_exists") or independent.get("is_valid_xml")
    file_modified = result.get("file_modified", False)
    valid_xml = result.get("is_valid_xml") or independent.get("is_valid_xml")

    if file_exists and valid_xml and file_modified:
        score += 10
        subscores["file_valid"] = True
        feedback_parts.append("File created and valid (10/10)")
    elif file_exists and valid_xml:
        score += 5
        subscores["file_valid"] = False
        feedback_parts.append("File is valid XML but may not be newly created (5/10)")
    else:
        subscores["file_valid"] = False
        feedback_parts.append("Output file missing or invalid XML (0/10)")

    # --- Criterion 2: BUG 1 fixed — Block 3 before Block 4 (20 pts) ---
    bug1_fixed = (
        result.get("bug1_flow_order_fixed")
        or independent.get("bug1_flow_order_fixed")
    )
    if bug1_fixed:
        score += 20
        subscores["bug1"] = True
        feedback_parts.append("BUG 1 FIXED: Compatible block (3) before Incompatible block (4) (20/20)")
    else:
        subscores["bug1"] = False
        flow_order = result.get("flow_order") or independent.get("flow_order", [])
        feedback_parts.append(
            f"BUG 1 NOT FIXED: Block 4 still before Block 3 in flow — "
            f"IAT D-score will be invalid. Flow order: {flow_order} (0/20)"
        )

    # --- Criterion 3: BUG 2 fixed — Practice nReps > 0 (15 pts) ---
    bug2_fixed = (
        result.get("bug2_practice_nreps_fixed")
        or independent.get("bug2_practice_nreps_fixed")
    )
    if bug2_fixed:
        score += 15
        subscores["bug2"] = True
        feedback_parts.append("BUG 2 FIXED: Practice block nReps > 0 (15/15)")
    else:
        subscores["bug2"] = False
        nreps = result.get("block2_nreps", "0")
        feedback_parts.append(f"BUG 2 NOT FIXED: Practice block2 nReps = {nreps!r} (0/15)")

    # --- Criterion 4: BUG 3 fixed — Code uses == (15 pts) ---
    bug3_fixed = (
        result.get("bug3_code_equals_fixed")
        or independent.get("bug3_code_equals_fixed")
    )
    if bug3_fixed:
        score += 15
        subscores["bug3"] = True
        feedback_parts.append("BUG 3 FIXED: Code component uses == for comparison (15/15)")
    else:
        subscores["bug3"] = False
        code_snippet = (
            result.get("code_component_each_frame")
            or independent.get("code_each_frame", "")
        )[:80]
        feedback_parts.append(
            f"BUG 3 NOT FIXED: Code component still uses = (assignment) not == (comparison). "
            f"Snippet: {code_snippet!r} (0/15)"
        )

    # --- Criterion 5: BUG 4 fixed — Label color uses $stim_color (15 pts) ---
    bug4_fixed = (
        result.get("bug4_color_ref_fixed")
        or independent.get("bug4_color_ref_fixed")
    )
    if bug4_fixed:
        score += 15
        subscores["bug4"] = True
        feedback_parts.append("BUG 4 FIXED: b2_label color references '$stim_color' (15/15)")
    else:
        subscores["bug4"] = False
        color_val = (
            result.get("b2_label_color_value")
            or independent.get("b2_label_color_value", "")
        )
        feedback_parts.append(
            f"BUG 4 NOT FIXED: b2_label still uses {color_val!r} instead of '$stim_color' (0/15)"
        )

    # --- Criterion 6: BUG 5 fixed — $participant in data filename (10 pts) ---
    bug5_fixed = (
        result.get("bug5_filename_fixed")
        or independent.get("bug5_filename_fixed")
    )
    if bug5_fixed:
        score += 10
        subscores["bug5"] = True
        feedback_parts.append("BUG 5 FIXED: Data filename references participant variable (10/10)")
    else:
        subscores["bug5"] = False
        fn = (
            result.get("data_filename_value")
            or independent.get("data_filename_value", "")
        )[:80]
        feedback_parts.append(
            f"BUG 5 NOT FIXED: Data filename {fn!r} doesn't use participant variable (0/10)"
        )

    # --- Criterion 7: Debrief routine added (15 pts) ---
    has_debrief = (
        result.get("has_debrief_routine")
        or independent.get("has_debrief_routine")
    )
    if has_debrief:
        score += 15
        subscores["debrief"] = True
        feedback_parts.append("Debrief routine added to experiment (15/15)")
    else:
        subscores["debrief"] = False
        feedback_parts.append("Debrief routine NOT found in experiment (0/15)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
