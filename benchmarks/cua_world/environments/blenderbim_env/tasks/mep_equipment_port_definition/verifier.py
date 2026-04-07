#!/usr/bin/env python3
"""
Verifier for mep_equipment_port_definition task.

Scoring rubric (100 points total, pass threshold = 70):
  - file_is_new          : 20 pts  (output IFC created/modified during this task)
  - boiler_exists        : 20 pts  (at least 1 IfcBoiler present)
  - ports_created        : 30 pts  (at least 2 IfcDistributionPort entities; partial 1=15 pts)
  - ports_linked         : 30 pts  (at least 2 IfcDistributionPort nested in boiler; partial 1=15 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mep_equipment_port_definition(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info."}

    # ── Copy result JSON from VM ──────────────────────────────────────────
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/mep_boiler_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run."}
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file: {e}"}
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
            "feedback": (
                "FAIL: Output IFC file /home/ga/BIMProjects/fzk_mep_boiler.ifc "
                "was not created. Score: 0/100."
            ),
        }

    # ── Check 1: File is newly created during this task session ───────────
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 20
        feedback_lines.append("PASS: Output IFC file was created/saved during this task session. (+20)")
    else:
        feedback_lines.append(
            "FAIL: Output file was not modified during the task "
            f"(file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)"
        )

    # ── Check 2: At least 1 IfcBoiler instantiated ────────────────────────
    n_boilers = result.get("n_boilers", 0)
    if n_boilers >= 1:
        score += 20
        feedback_lines.append(f"PASS: {n_boilers} IfcBoiler entity found. (+20)")
    else:
        feedback_lines.append("FAIL: No IfcBoiler found in output IFC. (+0)")

    # ── Check 3: At least 2 IfcDistributionPort instantiated ──────────────
    n_ports = result.get("n_ports", 0)
    if n_ports >= 2:
        score += 30
        feedback_lines.append(f"PASS: {n_ports} IfcDistributionPort entities found. (+30)")
    elif n_ports == 1:
        score += 15
        feedback_lines.append(f"PARTIAL: {n_ports}/2 IfcDistributionPort entities found. (+15)")
    else:
        feedback_lines.append("FAIL: No IfcDistributionPort entities found. (+0)")

    # ── Check 4: Ports structurally linked to the Boiler ──────────────────
    n_linked = result.get("n_linked_ports", 0)
    if n_linked >= 2:
        score += 30
        feedback_lines.append(f"PASS: {n_linked} ports successfully linked to boiler via IfcRelNests/IfcRelConnectsPortToElement. (+30)")
    elif n_linked == 1:
        score += 15
        feedback_lines.append(f"PARTIAL: {n_linked}/2 ports structurally linked to boiler. (+15)")
    else:
        feedback_lines.append("FAIL: No ports are properly structurally linked to the boiler. (+0)")

    # ── VLM Trajectory Verification (Informational / Anti-gaming Check) ───
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """You are analyzing screenshots from an agent performing a task in BlenderBIM.
The agent was asked to create an MEP Boiler and add distribution connection ports to it.
Look for evidence of the agent interacting with the Blender interface, the 3D viewport, and specifically the Bonsai/BlenderBIM MEP or Object Properties panels (or executing Python code).
Respond with JSON:
{
    "evidence_found": true/false,
    "reasoning": "brief explanation"
}"""
                vlm_result = query_vlm(prompt=prompt, images=images)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("evidence_found"):
                        feedback_lines.append("VLM: Confirmed trajectory evidence of agent interaction with BlenderBIM MEP tools.")
                    else:
                        feedback_lines.append("VLM: No clear visual evidence of MEP tool interaction in trajectory screenshots.")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")

    passed = score >= 70
    feedback_lines.append(
        f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 70)."
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }