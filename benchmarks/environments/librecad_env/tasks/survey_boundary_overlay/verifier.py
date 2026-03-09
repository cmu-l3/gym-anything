"""
Verifier for survey_boundary_overlay task.

A licensed land surveyor must overlay property boundary lines (with bearing/distance
callouts), building setback lines, utility easements, a north arrow, and a boundary
legend onto an architectural floor plan DXF file.

Scoring (100 pts total, pass threshold = 65):
  GATE  — output file exists AND is newer than task start          (0/fail)
  20 pts — Property boundary layer present (new layer)
  15 pts — Setback/zoning line layer present (new layer)
  20 pts — Boundary line entities >= 4
  20 pts — Bearing notation text >= 2 (N__°__'E / S__°__'W format)
  15 pts — Easement entities OR setback entities >= 2
  10 pts — Legend text OR north arrow found
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# ── scoring constants ──────────────────────────────────────────────────────────
MAX_SCORE = 100
PASS_THRESHOLD = 65

BOUNDARY_KW = ["PROPERTY", "BOUNDARY", "LOT", "PARCEL", "SURVEY", "C-PROP",
               "PROP-LINE", "PROPLINE", "LEGAL", "PLAT", "CADASTRAL"]
SETBACK_KW = ["SETBACK", "BUILDING LINE", "BLDG-LINE", "ZONING", "ZONE",
              "SET-BACK", "REQUIRED", "FRONT", "REAR", "SIDE"]
EASEMENT_KW = ["EASEMENT", "ESMT", "UTILITY", "ACCESS", "RIGHT-OF-WAY",
               "ROW", "DRAINAGE", "INGRESS", "EGRESS"]
BEARING_PATTERN = re.compile(
    r'\b[NSns]\s*\d+[\d°d\.\-\s]*[\'\"m]?\s*[EWew]\b',
    re.IGNORECASE
)


def _check_bearing_independent(output_file: str) -> list:
    """Re-parse DXF directly to find bearing text, independent of export script."""
    bearing_texts = []
    try:
        import ezdxf
        doc = ezdxf.readfile(output_file)
        msp = doc.modelspace()
        for entity in msp:
            text_val = None
            if entity.dxftype() == "TEXT":
                text_val = entity.dxf.text if hasattr(entity.dxf, "text") else ""
            elif entity.dxftype() == "MTEXT":
                if hasattr(entity, "plain_mtext"):
                    text_val = entity.plain_mtext()
                elif hasattr(entity.dxf, "text"):
                    text_val = entity.dxf.text
            if text_val and BEARING_PATTERN.search(text_val):
                bearing_texts.append(text_val.strip())
    except Exception:
        pass
    return bearing_texts


def verify_survey_boundary_overlay(traj, env_info, task_info):
    """Score the survey_boundary_overlay task."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "max_score": MAX_SCORE,
                "feedback": "copy_from_env unavailable", "criteria": {}}

    # ── copy result JSON from VM ───────────────────────────────────────────────
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/survey_boundary_overlay_result.json", tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "max_score": MAX_SCORE,
                "feedback": "Result JSON not found — export_result.sh did not run", "criteria": {}}
    except Exception as e:
        return {"passed": False, "score": 0, "max_score": MAX_SCORE,
                "feedback": f"Error reading result JSON: {e}", "criteria": {}}
    finally:
        try:
            os.unlink(tmp_json.name)
        except Exception:
            pass

    # ── GATE: output file must exist and be newer than task start ──────────────
    if not result.get("output_file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "max_score": MAX_SCORE,
            "feedback": "GATE FAILED: floorplan_survey.dxf was not created.",
            "criteria": {"gate": False},
        }

    task_start = result.get("task_start_timestamp", 0)
    file_mtime = result.get("output_file_mtime", 0)
    if task_start > 0 and file_mtime <= task_start:
        return {
            "passed": False,
            "score": 0,
            "max_score": MAX_SCORE,
            "feedback": (
                f"GATE FAILED: Output file predates task start "
                f"(mtime={file_mtime}, start={task_start})."
            ),
            "criteria": {"gate": False},
        }

    # ── scoring ────────────────────────────────────────────────────────────────
    score = 0
    criteria = {"gate": True}
    feedback_parts = []

    # Criterion 1 — property boundary layer present (20 pts)
    boundary_found = result.get("boundary_layer_found", False)
    boundary_names = result.get("boundary_layer_names", [])
    # Also accept if any new layer name mentions common survey terms
    if not boundary_found:
        for ln in result.get("new_layer_names", []):
            if any(kw in ln.upper() for kw in BOUNDARY_KW):
                boundary_found = True
                boundary_names.append(ln)
    if boundary_found:
        score += 20
        criteria["boundary_layer"] = True
        feedback_parts.append(f"Property boundary layer found: {boundary_names}")
    else:
        criteria["boundary_layer"] = False
        feedback_parts.append(
            "No property boundary layer found (expected layer with PROPERTY/BOUNDARY/LOT/SURVEY/etc.)"
        )

    # Criterion 2 — setback/zoning layer present (15 pts)
    setback_found = result.get("setback_layer_found", False)
    setback_names = result.get("setback_layer_names", [])
    if not setback_found:
        for ln in result.get("new_layer_names", []):
            if any(kw in ln.upper() for kw in SETBACK_KW):
                setback_found = True
                setback_names.append(ln)
    if setback_found:
        score += 15
        criteria["setback_layer"] = True
        feedback_parts.append(f"Setback/zoning layer found: {setback_names}")
    else:
        criteria["setback_layer"] = False
        feedback_parts.append(
            "No setback layer found (expected layer with SETBACK/ZONING/BLDG-LINE/etc.)"
        )

    # Criterion 3 — boundary line entities >= 4 (20 pts)
    boundary_lines = result.get("boundary_line_count", 0)
    new_entities = result.get("new_entity_count", 0)
    # Fallback: if boundary_lines=0 but new entities exist, be generous
    # (agent may not have used a specifically named layer)
    if boundary_lines >= 4:
        score += 20
        criteria["boundary_lines"] = True
        feedback_parts.append(f"Boundary line entities: {boundary_lines} (>= 4 required)")
    elif new_entities >= 8:
        # Partial: new entities exist, may just be on unnamed layer
        score += 10
        criteria["boundary_lines"] = "partial"
        feedback_parts.append(
            f"Only {boundary_lines} lines on named boundary layers, "
            f"but {new_entities} new entities total — partial credit"
        )
    else:
        criteria["boundary_lines"] = False
        feedback_parts.append(
            f"Insufficient boundary lines: {boundary_lines} found, 4 required"
        )

    # Criterion 4 — bearing notation text >= 2 (20 pts)
    bearing_count = result.get("bearing_text_count", 0)
    bearing_texts = result.get("bearing_texts", [])

    # Independent re-check via direct DXF parse
    if bearing_count < 2:
        try:
            tmp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix=".dxf")
            tmp_dxf.close()
            copy_from_env("/home/ga/Documents/LibreCAD/floorplan_survey.dxf", tmp_dxf.name)
            extra_bearings = _check_bearing_independent(tmp_dxf.name)
            if len(extra_bearings) > bearing_count:
                bearing_count = len(extra_bearings)
                bearing_texts = extra_bearings
        except Exception:
            pass
        finally:
            try:
                os.unlink(tmp_dxf.name)
            except Exception:
                pass

    if bearing_count >= 2:
        score += 20
        criteria["bearing_notation"] = True
        feedback_parts.append(
            f"Bearing notation found: {bearing_count} instances "
            f"(e.g. {bearing_texts[:2]})"
        )
    elif bearing_count == 1:
        score += 8
        criteria["bearing_notation"] = "partial"
        feedback_parts.append(
            f"Only 1 bearing notation found; 2 required for full credit"
        )
    else:
        criteria["bearing_notation"] = False
        feedback_parts.append(
            "No bearing notation found (expected N__°__'E / S__°__'W format)"
        )

    # Criterion 5 — easement OR setback entities >= 2 (15 pts)
    easement_entities = result.get("easement_entity_count", 0)
    setback_entity_count = 0
    # Count lines on setback layers from raw layer data
    # (export script only counts easement layer entities explicitly;
    #  setback entities counted indirectly via new entity count if setback layer exists)
    if easement_entities >= 2:
        score += 15
        criteria["easement_setback_entities"] = True
        feedback_parts.append(
            f"Easement/setback entities: {easement_entities} (>= 2 required)"
        )
    elif easement_entities >= 1 or (setback_found and new_entities >= 4):
        score += 7
        criteria["easement_setback_entities"] = "partial"
        feedback_parts.append(
            f"Only {easement_entities} easement entities on named layers; partial credit"
        )
    else:
        criteria["easement_setback_entities"] = False
        feedback_parts.append(
            "No easement or setback entities found on dedicated layers"
        )

    # Criterion 6 — legend text OR north arrow (10 pts)
    legend_found = result.get("legend_text_found", False)
    north_found = result.get("north_arrow_found", False)
    north_layer = result.get("north_arrow_layer_found", False)

    if legend_found or north_found or north_layer:
        score += 10
        criteria["legend_north_arrow"] = True
        details = []
        if legend_found:
            details.append("legend text")
        if north_found or north_layer:
            details.append("north arrow")
        feedback_parts.append(f"Survey annotations found: {', '.join(details)}")
    else:
        # Also check raw text content
        all_text = result.get("all_text_content", [])
        for t in all_text:
            t_up = t.upper()
            if any(kw in t_up for kw in ["LEGEND", "NOTES", "NORTH", "SURVEYOR"]):
                score += 10
                criteria["legend_north_arrow"] = True
                feedback_parts.append(f"Survey annotation text found: '{t[:50]}'")
                break
        else:
            criteria["legend_north_arrow"] = False
            feedback_parts.append(
                "No legend text or north arrow found"
            )

    # ── final result ───────────────────────────────────────────────────────────
    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "max_score": MAX_SCORE,
        "feedback": " | ".join(feedback_parts),
        "criteria": criteria,
        "details": {
            "new_entities": result.get("new_entity_count", 0),
            "new_layers": result.get("new_layer_names", []),
            "boundary_lines": result.get("boundary_line_count", 0),
            "bearing_count": bearing_count,
            "easement_count": result.get("easement_entity_count", 0),
            "file_size_bytes": result.get("file_size_bytes", 0),
        },
    }
