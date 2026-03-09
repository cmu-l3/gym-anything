#!/usr/bin/env python3
"""Verifier for complete_implant_workflow task.

Multi-criterion scoring (100 points total):
  Criterion 1 (15 pts): Project .bsp file exists and is substantial (>200KB)
  Criterion 2 (15 pts): Project file was modified after the task started
  Criterion 3 (20 pts): Project file is large enough to contain implant data (>500KB)
  Criterion 4 (15 pts): Screenshot .png file exists and is substantial (>50KB)
  Criterion 5 (20 pts): Project contains implant-related data (SQLite or size heuristic)
  Criterion 6 (15 pts): Measurement data present in the project

Pass threshold: 70 points

The verifier independently copies .bsp and .png files from the VM for anti-tamper
verification (does not rely solely on the export_result.ps1 JSON).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# Thresholds
BSP_MIN_SIZE_BASIC = 200 * 1024       # 200 KB — bare minimum for a DICOM project
BSP_MIN_SIZE_IMPLANT = 500 * 1024     # 500 KB — heuristic for DICOM + implant data
SCREENSHOT_MIN_SIZE = 50 * 1024       # 50 KB  — minimum for a meaningful screenshot
PASS_THRESHOLD = 70


def _safe_copy(copy_from_env, remote_path, local_path):
    """Attempt to copy a file from the VM. Returns True on success."""
    try:
        copy_from_env(remote_path, local_path)
        return os.path.exists(local_path) and os.path.getsize(local_path) > 0
    except Exception as e:
        logger.warning("Failed to copy %s: %s", remote_path, e)
        return False


def verify_complete_implant_workflow(traj, env_info, task_info):
    """Multi-criterion verifier for the complete implant workflow task."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # Step A: Retrieve the export JSON produced by export_result.ps1
    # ------------------------------------------------------------------
    result_json = {}
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        if _safe_copy(
            copy_from_env,
            r"C:\Users\Docker\Desktop\BlueSkyPlanTasks\complete_workflow_result.json",
            tmp_json.name,
        ):
            with open(tmp_json.name, "r", encoding="utf-8-sig") as f:
                result_json = json.load(f)
        else:
            feedback_parts.append("Export JSON not retrieved (post_task may not have run)")
    except Exception as e:
        feedback_parts.append(f"Export JSON parse error: {e}")
    finally:
        try:
            os.unlink(tmp_json.name)
        except OSError:
            pass

    # ------------------------------------------------------------------
    # Step B: Independently copy the .bsp file for anti-tamper checks
    # ------------------------------------------------------------------
    bsp_size = 0
    bsp_exists = False
    tmp_bsp = tempfile.NamedTemporaryFile(delete=False, suffix=".bsp")
    try:
        if _safe_copy(
            copy_from_env,
            r"C:\Users\Docker\Desktop\BlueSkyPlanTasks\complete_plan.bsp",
            tmp_bsp.name,
        ):
            bsp_size = os.path.getsize(tmp_bsp.name)
            bsp_exists = True
    finally:
        try:
            os.unlink(tmp_bsp.name)
        except OSError:
            pass

    # ------------------------------------------------------------------
    # Step C: Independently copy the screenshot for anti-tamper checks
    # ------------------------------------------------------------------
    ss_size = 0
    ss_exists = False
    tmp_ss = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
    try:
        if _safe_copy(
            copy_from_env,
            r"C:\Users\Docker\Desktop\BlueSkyPlanTasks\complete_plan_screenshot.png",
            tmp_ss.name,
        ):
            ss_size = os.path.getsize(tmp_ss.name)
            ss_exists = True
    finally:
        try:
            os.unlink(tmp_ss.name)
        except OSError:
            pass

    # ------------------------------------------------------------------
    # Criterion 1 (15 pts): Project .bsp file exists and is substantial
    # ------------------------------------------------------------------
    if bsp_exists and bsp_size >= BSP_MIN_SIZE_BASIC:
        score += 15
        feedback_parts.append(f"BSP file exists and substantial ({bsp_size:,} bytes)")
    elif bsp_exists and bsp_size > 0:
        score += 7
        feedback_parts.append(f"BSP file exists but small ({bsp_size:,} bytes, need >{BSP_MIN_SIZE_BASIC:,})")
    else:
        feedback_parts.append("BSP project file not found or empty")

    # ------------------------------------------------------------------
    # Criterion 2 (15 pts): Project file was modified after task start
    # ------------------------------------------------------------------
    task_start = result_json.get("task_start_time", 0)
    bsp_modified = result_json.get("bsp_file_modified", 0)

    if task_start > 0 and bsp_modified > 0:
        if bsp_modified >= task_start:
            score += 15
            feedback_parts.append("BSP file modified after task start")
        else:
            feedback_parts.append(
                f"BSP file NOT modified after task start "
                f"(start={task_start}, modified={bsp_modified})"
            )
    elif bsp_exists:
        # Can't verify timing but file exists -- give partial credit
        score += 8
        feedback_parts.append("BSP file exists but timestamp verification unavailable")
    else:
        feedback_parts.append("Cannot verify modification time (no BSP file)")

    # ------------------------------------------------------------------
    # Criterion 3 (20 pts): Project large enough to contain implant data
    #   The heuristic: a bare DICOM project is typically <400KB.
    #   Adding implants, panoramic adjustments, and measurements pushes
    #   the file well above 500KB.
    # ------------------------------------------------------------------
    if bsp_size >= BSP_MIN_SIZE_IMPLANT:
        score += 20
        feedback_parts.append(
            f"BSP file size suggests implant data present ({bsp_size:,} bytes > {BSP_MIN_SIZE_IMPLANT:,})"
        )
    elif bsp_size >= BSP_MIN_SIZE_BASIC:
        score += 8
        feedback_parts.append(
            f"BSP file moderate size ({bsp_size:,} bytes) -- may lack implant data"
        )
    else:
        feedback_parts.append("BSP file too small to contain implant data")

    # ------------------------------------------------------------------
    # Criterion 4 (15 pts): Screenshot file exists and is substantial
    # ------------------------------------------------------------------
    if ss_exists and ss_size >= SCREENSHOT_MIN_SIZE:
        score += 15
        feedback_parts.append(f"Screenshot exists and substantial ({ss_size:,} bytes)")
    elif ss_exists and ss_size > 0:
        score += 7
        feedback_parts.append(f"Screenshot exists but small ({ss_size:,} bytes, need >{SCREENSHOT_MIN_SIZE:,})")
    else:
        feedback_parts.append("Screenshot file not found or empty")

    # ------------------------------------------------------------------
    # Criterion 5 (20 pts): Implant-specific data in project
    #   Prefer SQLite analysis from the export JSON; fall back to
    #   size heuristic.
    # ------------------------------------------------------------------
    has_implant = result_json.get("has_implant_data", False)
    implant_rows = result_json.get("implant_table_rows", 0)

    if has_implant and implant_rows > 0:
        score += 20
        feedback_parts.append(f"Implant data confirmed via SQLite ({implant_rows} rows)")
    elif has_implant:
        score += 15
        feedback_parts.append("Implant data detected (SQLite table match, no row count)")
    elif bsp_size >= BSP_MIN_SIZE_IMPLANT:
        # File is large enough -- give partial credit via size heuristic
        score += 10
        feedback_parts.append("No SQLite implant confirmation, but file size suggestive")
    else:
        feedback_parts.append("No implant data detected in project")

    # ------------------------------------------------------------------
    # Criterion 6 (15 pts): Measurement data present in project
    # ------------------------------------------------------------------
    has_measurement = result_json.get("has_measurement_data", False)
    meas_rows = result_json.get("measurement_table_rows", 0)

    if has_measurement and meas_rows > 0:
        score += 15
        feedback_parts.append(f"Measurement data confirmed via SQLite ({meas_rows} rows)")
    elif has_measurement:
        score += 10
        feedback_parts.append("Measurement data detected (SQLite table match, no row count)")
    elif bsp_size >= BSP_MIN_SIZE_IMPLANT:
        # Large file may contain measurements embedded in other structures
        score += 5
        feedback_parts.append("No explicit measurement table, but large project may embed measurements")
    else:
        feedback_parts.append("No measurement data detected in project")

    # ------------------------------------------------------------------
    # Final verdict
    # ------------------------------------------------------------------
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
