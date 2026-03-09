#!/usr/bin/env python3
"""Verifier for implant_site_assessment task.

Scoring (100 points total):
  Criterion 1 (20 pts): .bsp project file exists and is substantial (>100 KB)
  Criterion 2 (20 pts): .bsp was modified after the task start timestamp
  Criterion 3 (25 pts): Multiple measurements detected in .bsp SQLite
  Criterion 4 (20 pts): Annotation/fiducial data present in .bsp SQLite
  Criterion 5 (15 pts): Exported cross-section images exist (>10 KB each)

Pass threshold: 70 points

Anti-tamper: The verifier independently copies the .bsp file and images
from the VM via copy_from_env, rather than trusting only the export JSON.
A do-nothing agent gets score 0 because no .bsp or images will exist.
"""

import json
import logging
import os
import sqlite3
import tempfile
import shutil
from typing import Any, Dict, List, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Minimum sizes to distinguish real output from empty/stub files
MIN_BSP_SIZE_BYTES = 100 * 1024  # 100 KB
MIN_IMAGE_SIZE_BYTES = 10 * 1024  # 10 KB

# Paths inside the Windows VM
RESULT_JSON_PATH = r"C:\Users\Docker\Desktop\BlueSkyPlanTasks\site_assessment_result.json"
BSP_PATH = r"C:\Users\Docker\Desktop\BlueSkyPlanTasks\site_assessment.bsp"
IMAGES_DIR = r"C:\Users\Docker\Desktop\BlueSkyPlanTasks\site_images"

# Keywords that indicate annotation/marker/fiducial data in BSP SQLite tables
ANNOTATION_KEYWORDS = [
    "annot", "markup", "marker", "point", "landmark", "label",
    "note", "nerve", "canal", "foramen", "fiducial", "drawing",
    "pin", "flag", "tag",
]

# Keywords that indicate measurement/distance data
MEASUREMENT_KEYWORDS = [
    "measur", "distance", "ruler", "line", "dimension",
    "length", "width", "height", "metric", "caliper",
]


def _try_copy(copy_from_env, remote_path: str, local_path: str) -> bool:
    """Attempt to copy a file from the VM; return True on success."""
    try:
        copy_from_env(remote_path, local_path)
        return os.path.exists(local_path) and os.path.getsize(local_path) > 0
    except Exception as exc:
        logger.debug("copy_from_env(%s) failed: %s", remote_path, exc)
        return False


def _check_sqlite_for_data(
    bsp_path: str, keywords: List[str]
) -> Tuple[bool, List[str], Dict]:
    """
    Open a .bsp (SQLite) file and check whether any table name or column name
    matches the given keywords AND contains at least one row.

    Returns (found: bool, table_hits: list[str], details: dict).
    """
    found = False
    table_hits = []
    details = {}

    try:
        conn = sqlite3.connect(bsp_path)
        cursor = conn.cursor()

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [row[0] for row in cursor.fetchall()]

        for table in tables:
            table_lower = table.lower()

            # Check table name against keywords
            name_match = any(kw in table_lower for kw in keywords)

            # Check column names against keywords
            col_match = False
            try:
                cursor.execute(f"PRAGMA table_info([{table}])")
                col_info = cursor.fetchall()
                col_names_lower = " ".join(c[1].lower() for c in col_info)
                col_match = any(kw in col_names_lower for kw in keywords)
            except Exception:
                pass

            if name_match or col_match:
                try:
                    cursor.execute(f"SELECT COUNT(*) FROM [{table}]")
                    row_count = cursor.fetchone()[0]
                    if row_count > 0:
                        found = True
                        match_type = "name" if name_match else "column"
                        table_hits.append(table)
                        details[table] = {
                            "match_type": match_type,
                            "row_count": row_count,
                        }
                except Exception:
                    pass

        # Fallback: check generic data tables for positional/measurement columns
        if not found:
            generic_keywords = ["object", "data", "item", "entity", "element"]
            for table in tables:
                table_lower = table.lower()
                if any(kw in table_lower for kw in generic_keywords):
                    try:
                        cursor.execute(f"SELECT COUNT(*) FROM [{table}]")
                        count = cursor.fetchone()[0]
                        if count > 0:
                            cursor.execute(f"PRAGMA table_info([{table}])")
                            cols = " ".join(c[1].lower() for c in cursor.fetchall())
                            if any(kw in cols for kw in keywords):
                                found = True
                                table_hits.append(table)
                                details[table] = {
                                    "match_type": "generic_column",
                                    "row_count": count,
                                }
                    except Exception:
                        pass

        conn.close()
    except Exception as exc:
        details["_error"] = str(exc)

    return found, table_hits, details


def verify_implant_site_assessment(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Multi-criterion verifier for the implant site assessment task.

    Uses copy_from_env to independently retrieve the .bsp file and images
    from the VM, then applies multi-criterion scoring.

    Scoring:
      Criterion 1 (20): .bsp exists and >100 KB
      Criterion 2 (20): .bsp modified after task start
      Criterion 3 (25): Multiple measurements detected in .bsp SQLite
      Criterion 4 (20): Annotation/fiducial data in .bsp SQLite
      Criterion 5 (15): Cross-section images exported (>10 KB each)

    Pass threshold: 70/100
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available -- framework error",
        }

    metadata = task_info.get("metadata", {})
    pass_threshold = metadata.get("pass_threshold", 70)

    temp_dir = tempfile.mkdtemp(prefix="verify_site_assessment_")
    feedback_parts = []
    score = 0
    details = {}

    try:
        # ==============================================================
        # Step 1: Fetch the result JSON produced by export_result.ps1
        # ==============================================================
        result_json_local = os.path.join(temp_dir, "site_assessment_result.json")
        result_data = None

        if _try_copy(copy_from_env, RESULT_JSON_PATH, result_json_local):
            try:
                with open(result_json_local, "r", encoding="utf-8-sig") as fh:
                    result_data = json.load(fh)
                logger.debug("Result JSON loaded successfully")
            except Exception as exc:
                logger.warning("Failed to parse result JSON: %s", exc)

        details["export_result_loaded"] = result_data is not None

        # ==============================================================
        # Step 2: Independently copy the .bsp file (anti-tamper)
        # ==============================================================
        bsp_local = os.path.join(temp_dir, "site_assessment.bsp")
        bsp_copied = _try_copy(copy_from_env, BSP_PATH, bsp_local)
        bsp_size = os.path.getsize(bsp_local) if bsp_copied else 0

        details["bsp_copied"] = bsp_copied
        details["bsp_size_bytes"] = bsp_size

        # ==============================================================
        # Step 3: Copy exported images (anti-tamper)
        # ==============================================================
        copied_images = []
        if result_data and result_data.get("image_files"):
            for img_info in result_data["image_files"]:
                img_name = img_info.get("name", "")
                if not img_name:
                    continue
                remote = f"{IMAGES_DIR}\\{img_name}"
                local = os.path.join(temp_dir, img_name)
                if _try_copy(copy_from_env, remote, local):
                    size_kb = os.path.getsize(local) / 1024.0
                    copied_images.append({"name": img_name, "size_kb": size_kb})
        else:
            # Try common image names if result JSON is missing
            for name in [
                "cross_section_1.png", "cross_section_2.png",
                "site_1.png", "site_2.png", "site_3.png",
                "assessment_1.png", "assessment_2.png",
            ]:
                remote = f"{IMAGES_DIR}\\{name}"
                local = os.path.join(temp_dir, name)
                if _try_copy(copy_from_env, remote, local):
                    size_kb = os.path.getsize(local) / 1024.0
                    copied_images.append({"name": name, "size_kb": size_kb})

        details["copied_images"] = copied_images

        # ==============================================================
        # CRITERION 1 (20 pts): .bsp exists and > 100 KB
        # ==============================================================
        bsp_size_kb = bsp_size / 1024.0 if bsp_size > 0 else 0

        # Cross-check with result_data if available
        if result_data:
            result_bsp_size_kb = result_data.get("bsp_size_kb", 0)
            bsp_size_kb = max(bsp_size_kb, result_bsp_size_kb)
            bsp_exists = result_data.get("bsp_exists", False) or bsp_copied
        else:
            bsp_exists = bsp_copied

        if bsp_exists and bsp_size >= MIN_BSP_SIZE_BYTES:
            score += 20
            feedback_parts.append(
                f"Criterion 1 PASS: .bsp exists and substantial ({bsp_size_kb:.1f} KB) (+20)"
            )
        elif bsp_exists and bsp_size > 0:
            # Partial credit for small but existing file
            score += 10
            feedback_parts.append(
                f"Criterion 1 PARTIAL: .bsp exists but small "
                f"({bsp_size_kb:.1f} KB, need >100 KB) (+10)"
            )
        else:
            feedback_parts.append("Criterion 1 FAIL: .bsp file not found")

        # ==============================================================
        # CRITERION 2 (20 pts): .bsp modified after task start
        # ==============================================================
        bsp_modified = False
        if result_data:
            bsp_modified = result_data.get("bsp_modified_after_start", False)

        if bsp_modified:
            score += 20
            feedback_parts.append(
                "Criterion 2 PASS: .bsp modified after task start (+20)"
            )
        elif bsp_exists:
            # File exists but modification cannot be confirmed;
            # give partial credit if the bsp_last_write_unix is nonzero
            bsp_last_write = result_data.get("bsp_last_write_unix", 0) if result_data else 0
            if bsp_last_write > 0:
                score += 10
                feedback_parts.append(
                    "Criterion 2 PARTIAL: .bsp exists, modification time uncertain (+10)"
                )
            else:
                feedback_parts.append(
                    "Criterion 2 FAIL: .bsp exists but not confirmed modified during task"
                )
        else:
            feedback_parts.append("Criterion 2 FAIL: no .bsp file to check")

        # ==============================================================
        # CRITERION 3 (25 pts): Multiple measurements in .bsp SQLite
        # ==============================================================
        has_measurement = False
        measurement_tables = []
        measurement_details = {}
        measurement_count = 0

        # Direct SQLite analysis on the independently copied .bsp
        if bsp_copied and bsp_size > 0:
            has_measurement, measurement_tables, measurement_details = (
                _check_sqlite_for_data(bsp_local, MEASUREMENT_KEYWORDS)
            )
            # Sum up row counts
            for tbl, info in measurement_details.items():
                if isinstance(info, dict) and "row_count" in info:
                    measurement_count += info["row_count"]

        # Fallback to export_result.ps1 data
        if not has_measurement and result_data:
            has_measurement = result_data.get("has_measurement_data", False)
            measurement_count = result_data.get("measurement_record_count", 0)

        details["measurement_analysis"] = {
            "found": has_measurement,
            "tables": measurement_tables,
            "record_count": measurement_count,
            "details": measurement_details,
        }

        if has_measurement and measurement_count >= 3:
            # Multiple measurements (ideally 6: 2 per site x 3 sites)
            score += 25
            feedback_parts.append(
                f"Criterion 3 PASS: multiple measurements found "
                f"({measurement_count} records) (+25)"
            )
        elif has_measurement and measurement_count >= 1:
            # Some measurements but fewer than expected
            score += 15
            feedback_parts.append(
                f"Criterion 3 PARTIAL: measurement data found but only "
                f"{measurement_count} record(s) (expected 3+) (+15)"
            )
        elif has_measurement:
            # Tables exist but empty
            score += 5
            feedback_parts.append(
                "Criterion 3 PARTIAL: measurement tables exist but empty (+5)"
            )
        elif bsp_copied and bsp_size >= MIN_BSP_SIZE_BYTES:
            # Large BSP but no recognized measurement tables
            score += 5
            feedback_parts.append(
                "Criterion 3 PARTIAL: BSP substantial but measurement tables "
                "not identified by keyword (+5)"
            )
        else:
            feedback_parts.append("Criterion 3 FAIL: no measurement data found")

        # ==============================================================
        # CRITERION 4 (20 pts): Annotation/fiducial data in .bsp SQLite
        # ==============================================================
        has_annotation = False
        annotation_tables = []
        annotation_details = {}
        annotation_count = 0

        if bsp_copied and bsp_size > 0:
            has_annotation, annotation_tables, annotation_details = (
                _check_sqlite_for_data(bsp_local, ANNOTATION_KEYWORDS)
            )
            for tbl, info in annotation_details.items():
                if isinstance(info, dict) and "row_count" in info:
                    annotation_count += info["row_count"]

        # Fallback to export_result.ps1 data
        if not has_annotation and result_data:
            has_annotation = result_data.get("has_annotation_data", False)
            annotation_count = result_data.get("annotation_record_count", 0)

        details["annotation_analysis"] = {
            "found": has_annotation,
            "tables": annotation_tables,
            "record_count": annotation_count,
            "details": annotation_details,
        }

        if has_annotation:
            score += 20
            tables_str = ", ".join(annotation_tables) if annotation_tables else "detected"
            feedback_parts.append(
                f"Criterion 4 PASS: annotation data found "
                f"({tables_str}, {annotation_count} records) (+20)"
            )
        elif bsp_copied and bsp_size >= MIN_BSP_SIZE_BYTES:
            # BSP is large enough that it likely contains data,
            # but keyword search did not match
            score += 5
            feedback_parts.append(
                "Criterion 4 PARTIAL: BSP substantial but annotation tables "
                "not identified by keyword (+5)"
            )
        else:
            feedback_parts.append("Criterion 4 FAIL: no annotation data found")

        # ==============================================================
        # CRITERION 5 (15 pts): Cross-section images exported (>10 KB)
        # ==============================================================
        # Count valid images from direct copy
        direct_valid = sum(
            1 for img in copied_images if img["size_kb"] > (MIN_IMAGE_SIZE_BYTES / 1024.0)
        )

        # Also use result_data count
        result_valid = 0
        if result_data:
            result_valid = result_data.get("valid_image_count", 0)

        effective_valid = max(direct_valid, result_valid)

        if effective_valid >= 2:
            score += 15
            feedback_parts.append(
                f"Criterion 5 PASS: {effective_valid} valid cross-section image(s) "
                f"exported (>= 2 required) (+15)"
            )
        elif effective_valid == 1:
            score += 8
            feedback_parts.append(
                f"Criterion 5 PARTIAL: only {effective_valid} valid image found "
                f"(2 required for full credit) (+8)"
            )
        else:
            feedback_parts.append(
                "Criterion 5 FAIL: no valid cross-section images found "
                f"in {IMAGES_DIR}"
            )

    finally:
        try:
            shutil.rmtree(temp_dir)
        except Exception:
            pass

    # ==================================================================
    # Final assessment
    # ==================================================================
    passed = score >= pass_threshold

    details["score_breakdown"] = {
        "criterion_1_bsp_exists": "see feedback",
        "criterion_2_bsp_modified": "see feedback",
        "criterion_3_measurements": "see feedback",
        "criterion_4_annotations": "see feedback",
        "criterion_5_images": "see feedback",
        "total_score": score,
        "pass_threshold": pass_threshold,
    }

    summary = f"Score: {score}/100"
    if passed:
        summary = f"PASSED -- {summary}"
    else:
        summary = f"FAILED (need >={pass_threshold}) -- {summary}"

    logger.info("implant_site_assessment: %s | %s", summary, " | ".join(feedback_parts))

    return {
        "passed": passed,
        "score": score,
        "feedback": summary + " | " + " | ".join(feedback_parts),
        "details": details,
    }
