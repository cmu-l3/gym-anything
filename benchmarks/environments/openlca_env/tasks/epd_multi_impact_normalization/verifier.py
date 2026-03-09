#!/usr/bin/env python3
"""
Verifier for EPD Multi-Impact Category Analysis task.

The agent must:
1. Import USLCI database and LCIA methods
2. Find a transport or agricultural process and build a product system
3. Run LCIA with >= 5 impact categories (GWP, Acidification, Eutrophication,
   Ozone Depletion, + at least 1 more)
4. Export ALL categories to ~/LCA_Results/epd_results.csv with
   category name, unit, and calculated value

Scoring (100 points total):
  Programmatic:
    - (15 pts) Database imported (> 15MB)
    - (15 pts) LCIA methods imported with >= 5 categories in DB
    - (20 pts) Product system created
    - (20 pts) EPD result file exported (size > 500 bytes)
    - (20 pts) File content: 4 required categories covered
    - (10 pts) 5th+ category present (EPD completeness)
  VLM:
    - (5 pts)  Trajectory shows multi-category LCIA workflow
    - (5 pts)  Final shows multi-category results table

Pass threshold: 60 points.
GATE: If fewer than 3 required categories in file AND score >= 60 → cap at 55.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are reviewing screenshots of an agent using openLCA to prepare multi-category LCA data for an Environmental Product Declaration (EPD) for a transport or agricultural process.

Expected workflow:
1. Import USLCI database and LCIA methods into openLCA
2. Find a transport process (truck, rail, barge, pipeline) or agricultural crop process
3. Create a product system for that process
4. Run LCIA calculation selecting a comprehensive method (TRACI 2.1 preferred) that covers 5+ categories
5. View the LCIA results table showing ALL impact categories at once
   (GWP, Acidification, Eutrophication, Ozone Depletion, Smog, Health, etc.)
6. Export ALL categories to a CSV file

Visual indicators of multi-category LCIA:
- A results table in openLCA showing 5+ rows for different impact categories
- Category names like Global Warming, Acidification, Eutrophication, Ozone Depletion visible together
- Numeric values with different units for each category

Assess:
- DB_IMPORTED: Evidence that database was imported
- PRODUCT_SYSTEM_CREATED: Evidence of product system
- MULTI_CATEGORY_LCIA: Evidence of LCIA with multiple categories visible simultaneously
- EXPORT_DONE: Evidence of file export with multiple categories

Return JSON:
{
  "db_imported": true/false,
  "product_system_created": true/false,
  "multi_category_lcia": true/false,
  "export_done": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "description"
}"""

FINAL_FRAME_PROMPT = """This is the final screenshot from an agent completing a multi-category EPD impact analysis in openLCA.

A successful final state shows one of:
- A CSV/spreadsheet with multiple rows, each representing a different impact category
  (e.g., Global Warming Potential, Acidification, Eutrophication, Ozone Depletion, Smog, etc.)
- openLCA results view showing a table of 5+ impact categories with numeric values and units
- A spreadsheet/text editor showing the exported EPD impact data

Key features to look for:
- MULTIPLE_CATEGORIES: 5 or more distinct environmental impact categories visible
- NUMERIC_VALUES: Numeric values with units visible for each category
- TRANSPORT_OR_AG: Process name suggests transport (truck/rail/barge) or agriculture (corn/wheat/soybean)
- STRUCTURED_DATA: Data appears organized in a table suitable for an EPD document

Return JSON:
{
  "multiple_categories": true/false,
  "numeric_values": true/false,
  "transport_or_ag": true/false,
  "structured_data": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "description of final state"
}"""


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None


def verify_epd_multi_impact_normalization(traj, env_info, task_info):
    """Verify EPD multi-category impact analysis was completed."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    subscores = {}

    # ── Criterion 1: Database imported (15 pts) ────────────────────────────────
    db_ok = result.get('db_found') and result.get('db_size_mb', 0) > 15
    if db_ok:
        score += 15
        subscores['database'] = True
        feedback.append(f"Database imported ({result.get('db_size_mb')}MB)")
    else:
        subscores['database'] = False
        feedback.append("Database not imported")

    # ── Criterion 2: LCIA methods with sufficient categories (15 pts) ──────────
    impact_cat_count = result.get('impact_cat_count', 0)
    if impact_cat_count >= 5:
        score += 15
        subscores['lcia_comprehensive'] = True
        feedback.append(f"Comprehensive LCIA methods imported ({impact_cat_count} categories)")
    elif impact_cat_count > 0:
        score += 8
        subscores['lcia_comprehensive'] = False
        feedback.append(f"LCIA methods imported but only {impact_cat_count} categories (need >= 5)")
    else:
        subscores['lcia_comprehensive'] = False
        feedback.append("LCIA methods not imported")

    # ── Criterion 3: Product system created (20 pts) ──────────────────────────
    ps_count = result.get('ps_count', 0)
    if ps_count >= 1:
        score += 20
        subscores['product_system'] = True
        feedback.append(f"Product system created (count={ps_count})")
    else:
        subscores['product_system'] = False
        feedback.append("No product system in database")

    # ── Criterion 4: EPD result file exported (20 pts) ───────────────────────
    has_file = (
        result.get('epd_file') and
        result.get('epd_file_size', 0) > 500
    )
    if has_file:
        score += 20
        subscores['file_exported'] = True
        feedback.append(
            f"EPD file exported ({result.get('epd_file_size')} bytes): "
            f"{os.path.basename(result.get('epd_file', ''))}"
        )
    elif result.get('epd_file_size', 0) > 100:
        score += 8
        subscores['file_exported'] = False
        feedback.append(f"File exported but too small ({result.get('epd_file_size')} bytes) for 5+ categories")
    elif result.get('current_result_count', 0) > result.get('initial_result_count', 0):
        score += 6
        subscores['file_exported'] = False
        feedback.append("New file in LCA_Results but not recognized or too small")
    else:
        subscores['file_exported'] = False
        feedback.append("No EPD result file exported to ~/LCA_Results/")

    # ── Criterion 5: Required categories in file (20 pts) ─────────────────────
    has_gwp = result.get('has_gwp_keyword', 0) == 1
    has_acid = result.get('has_acidification_keyword', 0) == 1
    has_eutroph = result.get('has_eutrophication_keyword', 0) == 1
    has_ozone = result.get('has_ozone_keyword', 0) == 1
    category_count = result.get('category_count', 0)

    # Score per required category
    cat_score = 0
    cat_parts = []
    if has_gwp:
        cat_score += 5
        cat_parts.append("GWP")
    if has_acid:
        cat_score += 5
        cat_parts.append("Acidification")
    if has_eutroph:
        cat_score += 5
        cat_parts.append("Eutrophication")
    if has_ozone:
        cat_score += 5
        cat_parts.append("Ozone Depletion")

    if cat_score > 0:
        score += cat_score
        subscores['required_categories'] = cat_score >= 15
        feedback.append(f"Required EPD categories: {', '.join(cat_parts)} ({cat_score}/20 pts)")
    else:
        subscores['required_categories'] = False
        if has_file:
            feedback.append("File exists but lacks required EPD impact category names")

    # ── Criterion 6: 5th+ category present (10 pts) ───────────────────────────
    has_extra = result.get('has_additional_category', 0) == 1
    if has_extra:
        score += 10
        subscores['fifth_category'] = True
        feedback.append("5th+ impact category present (smog/health/ecotox/particulates/etc.)")
    else:
        subscores['fifth_category'] = False
        if has_file:
            feedback.append("File lacks 5th+ impact category (smog, health, ecotox, etc.)")

    # ── VLM checks ────────────────────────────────────────────────────────────
    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')

    sampled = sample_frames(traj, num_samples=6) if sample_frames else []
    final_frame = get_final(traj) if get_final else None
    vlm_ok = query_vlm is not None

    # VLM: trajectory (5 pts)
    if vlm_ok and len(sampled) >= 2:
        traj_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=sampled)
        if traj_result:
            traj_pts = 0
            if traj_result.get('multi_category_lcia'):
                traj_pts += 3
            if traj_result.get('product_system_created'):
                traj_pts += 2
            score += traj_pts
            feedback.append(
                f"VLM trajectory: multi_cat={traj_result.get('multi_category_lcia')}, "
                f"ps={traj_result.get('product_system_created')}"
            )
        else:
            feedback.append("VLM trajectory unavailable")
    else:
        feedback.append("VLM trajectory: insufficient data")

    # VLM: final frame (5 pts)
    if vlm_ok and final_frame:
        final_result = _vlm_query(query_vlm, FINAL_FRAME_PROMPT, image=final_frame)
        if final_result:
            final_pts = 0
            if final_result.get('multiple_categories'):
                final_pts += 3
            if final_result.get('numeric_values'):
                final_pts += 2
            score += final_pts
            feedback.append(
                f"VLM final: multi_cat={final_result.get('multiple_categories')}, "
                f"values={final_result.get('numeric_values')}"
            )
        else:
            feedback.append("VLM final unavailable")
    else:
        feedback.append("VLM final: no frame")

    # ── GATE: Fewer than 3 required categories should not pass ────────────────
    required_cat_count = sum([has_gwp, has_acid, has_eutroph, has_ozone])
    passed = score >= 60
    if passed and required_cat_count < 3 and has_file:
        score = min(score, 55)
        passed = False
        feedback.append(
            f"GATE: Only {required_cat_count}/4 required EPD categories found — "
            "need GWP + Acidification + Eutrophication + Ozone Depletion"
        )

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "debug": {
            "ps_count": ps_count,
            "impact_cat_count": impact_cat_count,
            "epd_file_size": result.get('epd_file_size', 0),
            "category_count": category_count,
            "required_cat_count": required_cat_count,
        }
    }
