#!/usr/bin/env python3
"""
Verifier for mep_equipment_port_authoring task.

Required elements: >= 1 IfcChiller, >= 2 IfcDistributionPort nested to it,
Pset_ManufacturerTypeInformation with Manufacturer="ArcticFlow".

Scoring rubric (100 points total, pass threshold = 65):
  - file_is_new           : 15 pts (output IFC created during task, binary gate)
  - equipment_entity      : 20 pts (>= 1 IfcChiller / IfcEnergyConversionDevice)
  - port_entities         : 15 pts (>= 2 IfcDistributionPort; 8 pts for 1)
  - port_connectivity     : 20 pts (>= 2 ports nested to equipment via IfcRelNests; 10 pts for 1)
  - manufacturer_pset     : 15 pts (Manufacturer="ArcticFlow" assigned)
  - vlm_trajectory        : 15 pts (Blender UI interacted with during workflow)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to ensure they didn't just bypass the UI entirely
TRAJECTORY_PROMPT = """You are evaluating a sequence of screenshots from a user performing a task in Blender/Bonsai.
The goal of the task is to model a piece of MEP equipment (a chiller) and add connection ports.
Look through the provided sequence of screenshots.

Evaluate if the user interacted with the 3D viewport or the BlenderBIM/Bonsai interface panels (Properties panel, MEP tools, etc.).
Did the user do ANY of the following:
- Create or manipulate 3D geometry in the viewport
- Use the Bonsai tool panels to assign IFC classes
- Use the Bonsai MEP or Port authoring tools
- Use the Bonsai Property Set panels

Respond in JSON format:
{
    "ui_interaction_observed": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Briefly describe what UI elements or 3D manipulations you see."
}
"""

def verify_mep_equipment_port_authoring(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available in env_info."}

    # ── 1. Parse Programmatic Data ────────────────────────────────────────
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/chiller_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    # ── Critical gate: output file must exist ─────────────────────────────
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output IFC file /home/ga/BIMProjects/arcticflow_chiller.ifc was not created. Score: 0/100.",
        }

    # ── Check 1: File is newly created during this task session ───────────
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 15
        feedback_lines.append("PASS: Output IFC was created during this task session. (+15)")
    else:
        feedback_lines.append(f"FAIL: Output file not modified during task (file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)")

    # ── Check 2: Equipment Entity ─────────────────────────────────────────
    n_equip = result.get("n_equipment", 0)
    if n_equip >= 1:
        score += 20
        feedback_lines.append(f"PASS: {n_equip} Equipment entity found (IfcChiller/IfcEnergyConversionDevice). (+20)")
    else:
        feedback_lines.append("FAIL: No MEP Equipment entity found. (+0)")

    # ── Check 3: Port Entities ────────────────────────────────────────────
    n_ports = result.get("n_ports", 0)
    if n_ports >= 2:
        score += 15
        feedback_lines.append(f"PASS: {n_ports} Port entities found (>= 2 required). (+15)")
    elif n_ports == 1:
        score += 8
        feedback_lines.append(f"PARTIAL: {n_ports}/2 Port entities found. (+8)")
    else:
        feedback_lines.append("FAIL: No Port entities found. (+0)")

    # ── Check 4: Port Connectivity (Nested to Equipment) ──────────────────
    n_nested = result.get("n_nested_ports", 0)
    if n_nested >= 2:
        score += 20
        feedback_lines.append(f"PASS: {n_nested} Ports correctly nested to equipment. (+20)")
    elif n_nested == 1:
        score += 10
        feedback_lines.append(f"PARTIAL: {n_nested}/2 Ports correctly nested to equipment. (+10)")
    else:
        feedback_lines.append("FAIL: Ports are not logically connected to the equipment via IfcRelNests. (+0)")

    # ── Check 5: Manufacturer Property Set ────────────────────────────────
    has_pset = result.get("has_manufacturer_pset", False)
    if has_pset:
        score += 15
        feedback_lines.append("PASS: Pset_ManufacturerTypeInformation successfully assigned with 'ArcticFlow'. (+15)")
    else:
        feedback_lines.append("FAIL: Missing required manufacturer property set or value is incorrect. (+0)")

    # ── Check 6: VLM Trajectory (UI Interaction) ──────────────────────────
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = None
        if frames and callable(query_vlm):
            resp = query_vlm(images=frames, prompt=TRAJECTORY_PROMPT)
            if resp and resp.get("success"):
                vlm_res = resp.get("parsed", {})
        
        if vlm_res and vlm_res.get("ui_interaction_observed"):
            score += 15
            feedback_lines.append("PASS: VLM observed appropriate modeling/UI interaction. (+15)")
        else:
            feedback_lines.append("FAIL: VLM did not observe clear UI/modeling interaction (or VLM unavailable). (+0)")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM completely fails due to lack of API, we can gracefully grant points or leave it 0
        # Leaving it 0 ensures strictness, but we add a note
        feedback_lines.append(f"NOTE: VLM check failed or skipped ({str(e)[:50]}). (+0)")

    # ── Final Evaluation ──────────────────────────────────────────────────
    passed = score >= 65
    feedback_lines.append(f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 65).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }