#!/usr/bin/env python3
"""
Verifier for as_built_markup task.

An architectural drafter must prepare an as-built record drawing from a real
architectural floor plan (2-car garage). The task requires creating as-built
markup layers, adding a status stamp, and documenting field changes.

Scoring (100 points):
  - GATE: Output file exists and was created after task start (else score=0)
  - As-built themed layer present:                          20 pts
  - Change/notes/markup layer present:                      15 pts
  - As-built stamp text (status annotation) present:        20 pts
  - Field change text entities on new layers (>= 2):        20 pts
  - Minimum 5 new entities added vs baseline:               15 pts
  - File size > 50 KB (non-trivial content):                10 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_as_built_markup(traj, env_info, task_info):
    """Verify as-built markup task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_new_entities = metadata.get("min_new_entities", 5)

    # ---- Copy result JSON from VM ----
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/as_built_markup_result.json", tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result JSON not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp_json.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    # ---- GATE: Output file must exist and be newer than task start ----
    if not result.get("output_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file '/home/ga/Documents/LibreCAD/floorplan_asbuilt.dxf' not found",
        }

    if not result.get("file_modified_after_start", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but was NOT modified after task start — likely a pre-existing file, not created by agent",
        }

    # ---- Criterion 1: As-built themed layer present (20 pts) ----
    if result.get("asbuilt_layer_present", False):
        score += 20
        subscores["asbuilt_layer"] = True
        feedback_parts.append("As-built layer present (+20)")
    else:
        subscores["asbuilt_layer"] = False
        feedback_parts.append("No as-built layer found (0/20) — expected layer like 'AS-BUILT', 'RECORD', or 'FIELD-VERIFIED'")

    # ---- Criterion 2: Change/notes/markup layer present (15 pts) ----
    if result.get("change_or_note_layer_present", False):
        score += 15
        subscores["change_layer"] = True
        feedback_parts.append("Change/notes layer present (+15)")
    else:
        subscores["change_layer"] = False
        feedback_parts.append("No change/notes layer found (0/15) — expected layer like 'FIELD-CHANGES', 'REVISION', or 'NOTES'")

    # ---- Criterion 3: As-built stamp text present (20 pts) ----
    if result.get("asbuilt_stamp_text_present", False):
        score += 20
        subscores["stamp_text"] = True
        feedback_parts.append("As-built status stamp text found (+20)")
    else:
        subscores["stamp_text"] = False
        # Also check via independent re-analysis from the DXF file directly
        independent_stamp = _check_stamp_text_independent(copy_from_env)
        if independent_stamp:
            score += 20
            subscores["stamp_text"] = True
            feedback_parts.append("As-built status stamp text found (independent check) (+20)")
        else:
            feedback_parts.append("As-built stamp text not found (0/20) — expected 'AS-BUILT', 'RECORD DRAWING', or similar")

    # ---- Criterion 4: Field change text on new layers (>= 2 entities) (20 pts) ----
    field_change_count = result.get("field_change_text_count", 0)
    if field_change_count >= 2:
        score += 20
        subscores["field_change_text"] = True
        feedback_parts.append(f"Field change documentation found ({field_change_count} entries) (+20)")
    elif field_change_count == 1:
        score += 10
        subscores["field_change_text"] = "partial"
        feedback_parts.append("Only 1 field change note found (10/20) — needed at least 2")
    else:
        subscores["field_change_text"] = False
        feedback_parts.append("No field change documentation found on as-built layers (0/20)")

    # ---- Criterion 5: Minimum new entities added (15 pts) ----
    new_entities = result.get("new_entity_count", 0)
    if new_entities >= min_new_entities:
        score += 15
        subscores["new_entities"] = True
        feedback_parts.append(f"{new_entities} new entities added vs baseline (+15)")
    else:
        subscores["new_entities"] = False
        feedback_parts.append(f"Only {new_entities} new entities added (0/15) — needed {min_new_entities}+")

    # ---- Criterion 6: File size > 50KB (non-trivial output) (10 pts) ----
    file_size = result.get("file_size_bytes", 0)
    if file_size > 50000:
        score += 10
        subscores["file_size"] = True
        feedback_parts.append(f"File is substantial ({file_size:,} bytes) (+10)")
    else:
        subscores["file_size"] = False
        feedback_parts.append(f"File too small ({file_size:,} bytes < 50,000) (0/10)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }


def _check_stamp_text_independent(copy_from_env):
    """Independently copy and re-analyze the DXF to verify stamp text exists."""
    try:
        tmp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix=".dxf")
        tmp_dxf.close()
        copy_from_env("/home/ga/Documents/LibreCAD/floorplan_asbuilt.dxf", tmp_dxf.name)

        try:
            import ezdxf
            doc = ezdxf.readfile(tmp_dxf.name)
            msp = doc.modelspace()
            stamp_kw = ["AS-BUILT", "AS BUILT", "ASBUILT", "RECORD DRAWING",
                        "FOR RECORD", "RECORD OF CONSTRUCTION", "FIELD VERIFIED",
                        "AS CONSTRUCTED", "ISSUED FOR RECORD"]
            for e in msp:
                try:
                    txt = ""
                    if e.dxftype() == "TEXT":
                        txt = e.dxf.text.strip().upper()
                    elif e.dxftype() == "MTEXT":
                        txt = e.text.strip().upper()
                    if txt and any(kw in txt for kw in stamp_kw):
                        return True
                except Exception:
                    pass
        except ImportError:
            # ezdxf not available on host — fall back to text search in raw file
            with open(tmp_dxf.name, "rb") as f:
                raw = f.read(50000).upper()
            stamp_kw_bytes = [b"AS-BUILT", b"AS BUILT", b"RECORD DRAWING", b"FIELD VERIFIED"]
            return any(kw in raw for kw in stamp_kw_bytes)
    except Exception as e:
        logger.warning(f"Independent stamp check failed: {e}")
    finally:
        try:
            os.unlink(tmp_dxf.name)
        except Exception:
            pass
    return False
