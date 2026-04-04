"""
Verifier for electrical_panel_schedule task.

An electrical engineering technician must create a complete residential electrical
panel schedule on an architectural floor plan: panel schedule table, branch circuit
annotations, load calculations, main breaker rating, circuit descriptions, and
electrical notes.

Scoring (100 pts total, pass threshold = 60):
  GATE  — output file exists AND is newer than task start          (0/fail)
  20 pts — E-PANEL or equivalent panel schedule layer present
  15 pts — Branch circuit layer or annotations present
  20 pts — Circuit descriptions >= 4 (lighting, receptacles, HVAC etc.)
  20 pts — Load calculation text present (watts/amps values)
  15 pts — Main breaker/panel rating annotation (e.g., "200A MAIN")
  10 pts — Electrical notes or specifications text
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

# ── scoring constants ──────────────────────────────────────────────────────────
MAX_SCORE = 100
PASS_THRESHOLD = 60

PANEL_KW = ["E-PANEL", "PANEL", "SCHEDULE", "ELEC-PANEL", "PANELBOARD",
            "LOADCENTER", "LOAD CENTER", "LOAD-CENTER"]
CIRCUIT_KW = ["E-CIRCUIT", "CIRCUIT", "BRANCH", "E-BRANCH", "ELEC-CKT",
              "CKT", "WIRING", "E-WIRE", "ELEC"]

LOAD_PATTERN = re.compile(
    r'\b\d+\.?\d*\s*(?:W\b|VA\b|KW\b|kW\b|KVA\b|kVA\b|A\b|AMP\b|AMPS\b|WATTS\b)',
    re.IGNORECASE
)
MAIN_BREAKER_PATTERN = re.compile(
    r'\b(?:200|150|100|60)\s*(?:A\b|AMP\b|AMPS\b)',
    re.IGNORECASE
)
CIRCUIT_DESC_KW = [
    "LIGHTING", "RECEPTACLE", "OUTLET", "HVAC", "A/C", "DRYER",
    "WASHER", "RANGE", "OVEN", "DISHWASHER", "MICROWAVE", "REFRIGERATOR",
    "GARAGE", "EXTERIOR", "KITCHEN", "BATH", "BEDROOM", "GENERAL",
    "SPARE", "SPACE", "RESERVED", "SMOKE", "GFI", "GFCI", "POWER"
]
NOTE_KW = ["NOTE", "SPEC", "REQUIRE", "INSTALL", "GENERAL", "ALL WIRING",
           "CONDUIT", "NEC", "CODE", "GROUNDING", "NEUTRAL"]


def _check_load_text_independent(output_file: str) -> list:
    """Re-parse DXF directly to find load calculation text."""
    load_texts = []
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
            if text_val and LOAD_PATTERN.search(text_val):
                load_texts.append(text_val.strip())
    except Exception:
        pass
    return load_texts


def verify_electrical_panel_schedule(traj, env_info, task_info):
    """Score the electrical_panel_schedule task."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "max_score": MAX_SCORE,
                "feedback": "copy_from_env unavailable", "criteria": {}}

    # ── copy result JSON from VM ───────────────────────────────────────────────
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/electrical_panel_schedule_result.json", tmp_json.name)
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
            "feedback": "GATE FAILED: floorplan_electrical.dxf was not created.",
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

    # Criterion 1 — panel schedule layer present (20 pts)
    panel_found = result.get("panel_layer_found", False)
    panel_names = result.get("panel_layer_names", [])

    if not panel_found:
        for ln in result.get("new_layer_names", []):
            if any(kw in ln.upper() for kw in PANEL_KW):
                panel_found = True
                panel_names.append(ln)

    if panel_found:
        score += 20
        criteria["panel_layer"] = True
        feedback_parts.append(f"Panel schedule layer found: {panel_names}")
    else:
        criteria["panel_layer"] = False
        feedback_parts.append(
            "No panel schedule layer found (expected E-PANEL/PANEL/SCHEDULE/etc.)"
        )

    # Criterion 2 — circuit layer or branch circuit annotations (15 pts)
    circuit_found = result.get("circuit_layer_found", False)
    circuit_names = result.get("circuit_layer_names", [])
    circuit_num_count = result.get("circuit_number_count", 0)

    if not circuit_found:
        for ln in result.get("new_layer_names", []):
            if any(kw in ln.upper() for kw in CIRCUIT_KW):
                circuit_found = True
                circuit_names.append(ln)

    if circuit_found or circuit_num_count >= 3:
        score += 15
        criteria["circuit_layer"] = True
        if circuit_found:
            feedback_parts.append(f"Circuit layer found: {circuit_names}")
        else:
            feedback_parts.append(
                f"Circuit numbers annotated: {circuit_num_count} (no dedicated layer, but annotations present)"
            )
    elif circuit_num_count >= 1:
        score += 7
        criteria["circuit_layer"] = "partial"
        feedback_parts.append(
            f"Only {circuit_num_count} circuit number annotations; no dedicated circuit layer"
        )
    else:
        criteria["circuit_layer"] = False
        feedback_parts.append(
            "No circuit layer or circuit number annotations found"
        )

    # Criterion 3 — circuit descriptions >= 4 (20 pts)
    circuit_desc_count = result.get("circuit_description_count", 0)
    circuit_descs = result.get("circuit_descriptions", [])

    # Also scan all text content for circuit description keywords
    if circuit_desc_count < 4:
        found_kws = set()
        for t in result.get("all_text_content", []):
            t_up = t.upper()
            for kw in CIRCUIT_DESC_KW:
                if kw in t_up:
                    found_kws.add(kw)
        circuit_desc_count = max(circuit_desc_count, len(found_kws))

    if circuit_desc_count >= 4:
        score += 20
        criteria["circuit_descriptions"] = True
        feedback_parts.append(
            f"Circuit descriptions: {circuit_desc_count} found "
            f"(e.g. {circuit_descs[:3]})"
        )
    elif circuit_desc_count >= 2:
        score += 10
        criteria["circuit_descriptions"] = "partial"
        feedback_parts.append(
            f"Only {circuit_desc_count} circuit descriptions; 4 required for full credit"
        )
    else:
        criteria["circuit_descriptions"] = False
        feedback_parts.append(
            f"Insufficient circuit descriptions: {circuit_desc_count} found, 4 required "
            f"(LIGHTING, RECEPTACLE, HVAC, KITCHEN, etc.)"
        )

    # Criterion 4 — load calculation text present (20 pts)
    load_count = result.get("load_text_count", 0)
    load_texts = result.get("load_texts", [])

    # Independent re-check via direct DXF parse
    if load_count < 1:
        try:
            tmp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix=".dxf")
            tmp_dxf.close()
            copy_from_env("/home/ga/Documents/LibreCAD/floorplan_electrical.dxf", tmp_dxf.name)
            extra_loads = _check_load_text_independent(tmp_dxf.name)
            if len(extra_loads) > load_count:
                load_count = len(extra_loads)
                load_texts = extra_loads
        except Exception:
            pass
        finally:
            try:
                os.unlink(tmp_dxf.name)
            except Exception:
                pass

    if load_count >= 3:
        score += 20
        criteria["load_calculations"] = True
        feedback_parts.append(
            f"Load calculations: {load_count} values found "
            f"(e.g. {load_texts[:2]})"
        )
    elif load_count >= 1:
        score += 10
        criteria["load_calculations"] = "partial"
        feedback_parts.append(
            f"Only {load_count} load value(s) found; 3 required for full credit "
            f"(e.g. {load_texts[:2]})"
        )
    else:
        criteria["load_calculations"] = False
        feedback_parts.append(
            "No load calculation values found (expected W/VA/A/KW values)"
        )

    # Criterion 5 — main breaker/panel rating annotation (15 pts)
    main_breaker = result.get("main_breaker_found", False)
    main_texts = result.get("main_breaker_texts", [])

    # Also scan all text for main breaker patterns
    if not main_breaker:
        for t in result.get("all_text_content", []):
            if MAIN_BREAKER_PATTERN.search(t) or ("MAIN" in t.upper() and re.search(r'\d+', t)):
                main_breaker = True
                main_texts.append(t.strip())
                break

    if main_breaker:
        score += 15
        criteria["main_breaker_rating"] = True
        feedback_parts.append(
            f"Main breaker/panel rating found: {main_texts[:2]}"
        )
    else:
        criteria["main_breaker_rating"] = False
        feedback_parts.append(
            "No main breaker rating found (expected '200A', '100 AMP MAIN', etc.)"
        )

    # Criterion 6 — electrical notes or specifications (10 pts)
    note_count = result.get("electrical_note_count", 0)
    notes_layer = result.get("notes_layer_found", False)

    # Also scan all text content
    if note_count < 1:
        for t in result.get("all_text_content", []):
            t_up = t.upper()
            if any(kw in t_up for kw in NOTE_KW) and len(t) > 5:
                note_count += 1

    if note_count >= 2 or notes_layer:
        score += 10
        criteria["electrical_notes"] = True
        if notes_layer:
            feedback_parts.append(f"Electrical notes layer found: {result.get('notes_layer_names', [])}")
        else:
            feedback_parts.append(f"Electrical notes/specs text found: {note_count} instances")
    elif note_count >= 1:
        score += 5
        criteria["electrical_notes"] = "partial"
        feedback_parts.append(f"Only {note_count} note entry; 2 needed for full credit")
    else:
        criteria["electrical_notes"] = False
        feedback_parts.append("No electrical notes or specifications found")

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
            "panel_table_lines": result.get("panel_table_lines", 0),
            "circuit_descriptions": circuit_desc_count,
            "load_count": load_count,
            "main_breaker_found": main_breaker,
            "file_size_bytes": result.get("file_size_bytes", 0),
        },
    }
