#!/usr/bin/env python3
"""
Verifier for hvac_system_overlay task.

A mechanical engineer must overlay a complete HVAC ductwork system on a real
architectural floor plan of a 2-car garage being converted to a workshop.
The task requires creating multiple HVAC layers, routing duct centerlines,
marking diffuser locations, and adding duct sizing callouts.

Scoring (100 points):
  - GATE: Output file exists and was created after task start (else score=0)
  - Supply air layer present:                                   20 pts
  - Return air layer present:                                   15 pts
  - Supply duct line entities (>= 5 on supply layer):           20 pts
  - Diffuser/grille symbols — circles anywhere (>= 3):          20 pts
  - Duct sizing text callouts (>= 3 entries):                   15 pts
  - Equipment label OR notes layer with system notes:           10 pts

Pass threshold: 65 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_hvac_system_overlay(traj, env_info, task_info):
    """Verify HVAC overlay task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_supply = metadata.get("min_supply_entities", 5)
    min_circles = metadata.get("min_diffuser_circles", 3)
    min_sizing = metadata.get("min_sizing_text", 3)

    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/hvac_system_overlay_result.json", tmp_json.name)
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

    # ---- GATE ----
    if not result.get("output_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file '/home/ga/Documents/LibreCAD/floorplan_hvac.dxf' not found",
        }

    if not result.get("file_modified_after_start", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but predates task start — not created by agent",
        }

    # ---- Criterion 1: Supply air layer (20 pts) ----
    if result.get("hvac_supply_layer_present", False):
        score += 20
        subscores["supply_layer"] = True
        feedback_parts.append("Supply air layer present (+20)")
    else:
        subscores["supply_layer"] = False
        feedback_parts.append("No supply air layer found (0/20) — expected layer with 'SUPPLY', 'SA', or 'HVAC-S'")

    # ---- Criterion 2: Return air layer (15 pts) ----
    if result.get("hvac_return_layer_present", False):
        score += 15
        subscores["return_layer"] = True
        feedback_parts.append("Return air layer present (+15)")
    else:
        subscores["return_layer"] = False
        feedback_parts.append("No return air layer found (0/15) — expected layer with 'RETURN', 'RA', or 'HVAC-R'")

    # ---- Criterion 3: Duct line entities on supply layer (20 pts) ----
    supply_lines = result.get("supply_line_count", 0)
    # Also count total new entities as proxy if no explicit supply layer
    new_entities = result.get("new_entity_count", 0)
    if supply_lines >= min_supply:
        score += 20
        subscores["duct_lines"] = True
        feedback_parts.append(f"{supply_lines} supply duct line segments (+20)")
    elif supply_lines >= 2:
        score += 10
        subscores["duct_lines"] = "partial"
        feedback_parts.append(f"Only {supply_lines} supply duct lines (10/20) — needed {min_supply}+")
    elif new_entities >= min_supply:
        # Partial credit if the new lines exist but aren't on a named supply layer
        score += 10
        subscores["duct_lines"] = "partial"
        feedback_parts.append(f"{new_entities} new entities but not on named supply layer (10/20)")
    else:
        subscores["duct_lines"] = False
        feedback_parts.append(f"Insufficient duct line entities ({supply_lines}) (0/20)")

    # ---- Criterion 4: Diffuser/grille symbols (circles >= 3) (20 pts) ----
    total_circles = result.get("total_circle_count", 0)
    circles_on_hvac = result.get("circle_count_on_hvac_layers", 0)

    # Use total circles since diffusers may be on any layer
    # But subtract baseline circles (the original drawing has arcs/circles we need to account for)
    # We'll use the count of circles on new layers as primary, with total as backup
    if circles_on_hvac >= min_circles:
        score += 20
        subscores["diffusers"] = True
        feedback_parts.append(f"{circles_on_hvac} diffuser symbols on HVAC layers (+20)")
    elif total_circles >= min_circles and result.get("new_entity_count", 0) >= 3:
        # Some circles may exist from original drawing; if new entities were added, partial credit
        score += 10
        subscores["diffusers"] = "partial"
        feedback_parts.append(f"Circles found ({total_circles} total) but not confirmed on HVAC layers (10/20)")
    else:
        subscores["diffusers"] = False
        feedback_parts.append(f"Insufficient diffuser symbols — found {total_circles} total circles, need {min_circles}+ (0/20)")

    # ---- Criterion 5: Duct sizing text callouts (15 pts) ----
    sizing_count = result.get("duct_sizing_text_count", 0)
    if sizing_count >= min_sizing:
        score += 15
        subscores["sizing_text"] = True
        feedback_parts.append(f"{sizing_count} duct sizing callouts found (+15)")
    elif sizing_count >= 1:
        score += 7
        subscores["sizing_text"] = "partial"
        feedback_parts.append(f"Only {sizing_count} duct sizing callout(s) (7/15) — needed {min_sizing}+")
    else:
        subscores["sizing_text"] = False
        feedback_parts.append(f"No duct sizing callouts found (0/15) — expected '12x8', '300 CFM', etc.")

    # ---- Criterion 6: Equipment label OR notes/system notes (10 pts) ----
    has_equip = result.get("equipment_label_present", False)
    has_notes = result.get("notes_text_present", False)
    has_equip_layer = result.get("hvac_equip_or_notes_layer_present", False)

    if has_equip or (has_notes and has_equip_layer):
        score += 10
        subscores["equipment_notes"] = True
        feedback_parts.append("Equipment label or system notes found (+10)")
    elif has_notes:
        score += 5
        subscores["equipment_notes"] = "partial"
        feedback_parts.append("System notes found but no dedicated layer (5/10)")
    else:
        subscores["equipment_notes"] = False
        feedback_parts.append("No equipment labels or system notes found (0/10)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
