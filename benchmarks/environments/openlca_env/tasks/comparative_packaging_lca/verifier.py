#!/usr/bin/env python3
"""
Verifier for Comparative Packaging LCA task.

The agent must:
1. Import USLCI database and LCIA methods into openLCA
2. Build product systems for BOTH glass bottle and aluminum can manufacturing
3. Run LCIA for both with 3+ impact categories (including GWP)
4. Export comparison results to ~/LCA_Results/packaging_comparison.csv

Scoring (100 points total):
  Programmatic:
    - (15 pts) Database imported (DB size > 15MB, impact categories loaded)
    - (15 pts) LCIA methods imported (impact_cat_count > 0)
    - (25 pts) TWO product systems created (ps_count >= 2)
    - (20 pts) Comparison file exported (exists, size > 100 bytes)
    - (15 pts) File content: both packaging types represented + GWP data
  VLM:
    - (5 pts)  Trajectory shows full comparative workflow
    - (5 pts)  Final state shows LCIA results

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# ── VLM Prompts ────────────────────────────────────────────────────────────────

TRAJECTORY_PROMPT = """You are reviewing screenshots from an agent using openLCA to conduct a comparative Life Cycle Assessment (LCA) of two packaging materials: glass bottles vs aluminum cans.

A successful comparative LCA workflow includes:
1. Importing a database (USLCI or similar) and LCIA methods
2. Creating TWO product systems — one for glass packaging, one for aluminum/can packaging
3. Running LCIA calculations for each product system (selecting an impact method like TRACI or ReCiPe)
4. Viewing results showing multiple impact categories (Global Warming, Acidification, etc.)
5. Exporting a comparison file (CSV or Excel)

Based on the sequence of screenshots, assess:
- WORKFLOW_STARTED: Did the agent open a database or import data?
- TWO_SYSTEMS_CREATED: Is there evidence of two separate product systems?
- LCIA_CALCULATED: Were LCIA calculations run (calculation dialog or results view)?
- COMPARISON_EXPORTED: Did the agent export a comparison file?
- MEANINGFUL_PROGRESSION: Do the frames show genuine LCA work progressing?

Return JSON:
{
  "workflow_started": true/false,
  "two_systems_created": true/false,
  "lcia_calculated": true/false,
  "comparison_exported": true/false,
  "meaningful_progression": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "brief description of what was observed"
}"""

FINAL_FRAME_PROMPT = """This is the final screenshot from an agent that should have completed a comparative LCA in openLCA for glass vs aluminum packaging.

A successful final state shows one of:
- A CSV/Excel file open showing environmental impact scores for both packaging types
- openLCA results view with LCIA impact categories and numeric values visible
- A file manager or text editor showing the exported comparison data
- openLCA with a results editor showing both product system results

Check:
- RESULTS_VISIBLE: Are LCIA result values (numbers with units) visible?
- COMPARISON_DATA: Is there data representing two different alternatives/systems?
- GWP_SHOWN: Is Global Warming Potential or CO2-equivalent values shown?
- EXPORT_COMPLETE: Is there evidence a file was saved/exported?

Return JSON:
{
  "results_visible": true/false,
  "comparison_data": true/false,
  "gwp_shown": true/false,
  "export_complete": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "what you see in the final screenshot"
}"""


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query error: {e}")
    return None


def verify_comparative_packaging_lca(traj, env_info, task_info):
    """Verify the comparative packaging LCA task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # ── Load result JSON ───────────────────────────────────────────────────────
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Export file not found — did the task run?"}
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
        subscores['database_imported'] = True
        feedback.append(f"Database imported ({result.get('db_size_mb')}MB)")
    else:
        subscores['database_imported'] = False
        feedback.append("Database not found or too small (< 15MB)")

    # ── Criterion 2: LCIA methods imported (15 pts) ───────────────────────────
    lcia_ok = result.get('impact_cat_count', 0) > 0
    if lcia_ok:
        score += 15
        subscores['lcia_imported'] = True
        feedback.append(f"LCIA methods imported ({result.get('impact_cat_count')} categories)")
    else:
        subscores['lcia_imported'] = False
        feedback.append("LCIA methods not imported (no impact categories in DB)")

    # ── Criterion 3: TWO product systems created (25 pts) ─────────────────────
    ps_count = result.get('ps_count', 0)
    if ps_count >= 2:
        score += 25
        subscores['two_product_systems'] = True
        feedback.append(f"Two product systems created (ps_count={ps_count})")
    elif ps_count == 1:
        score += 10
        subscores['two_product_systems'] = False
        feedback.append("Only ONE product system created — need two (glass + aluminum)")
    else:
        subscores['two_product_systems'] = False
        feedback.append("No product systems found in database")

    # ── Criterion 4: Comparison file exported (20 pts) ────────────────────────
    has_file = (
        result.get('comparison_file') and
        result.get('comparison_file_size', 0) > 100
    )
    if has_file:
        score += 20
        subscores['file_exported'] = True
        feedback.append(
            f"Comparison file exported ({result.get('comparison_file_size')} bytes): "
            f"{os.path.basename(result.get('comparison_file', ''))}"
        )
    elif result.get('current_result_count', 0) > result.get('initial_result_count', 0):
        score += 8
        subscores['file_exported'] = False
        feedback.append("New file in LCA_Results but too small or not found by verifier")
    else:
        subscores['file_exported'] = False
        feedback.append("No comparison file exported to ~/LCA_Results/")

    # ── Criterion 5: File content quality (15 pts) ────────────────────────────
    has_glass = result.get('has_glass_keyword', 0) == 1
    has_alum = result.get('has_aluminum_keyword', 0) == 1
    has_gwp = result.get('has_gwp_keyword', 0) == 1
    row_count = result.get('comparison_row_count', 0)

    content_score = 0
    content_details = []
    if has_glass:
        content_score += 5
        content_details.append("glass data present")
    if has_alum:
        content_score += 5
        content_details.append("aluminum data present")
    if has_gwp:
        content_score += 5
        content_details.append("GWP data present")

    if content_score > 0:
        score += content_score
        subscores['content_quality'] = content_score >= 10
        feedback.append(f"File content: {', '.join(content_details)} (rows with data: {row_count})")
    elif has_file:
        feedback.append("File exported but lacks packaging comparison content")
        subscores['content_quality'] = False
    else:
        subscores['content_quality'] = False

    # ── VLM Checks ────────────────────────────────────────────────────────────
    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')

    sampled = sample_frames(traj, num_samples=6) if sample_frames else []
    final_frame = get_final(traj) if get_final else None
    vlm_ok = query_vlm is not None

    # VLM Check: trajectory (5 pts)
    if vlm_ok and len(sampled) >= 2:
        traj_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=sampled)
        if traj_result:
            traj_score = 0
            if traj_result.get('workflow_started'):
                traj_score += 1
            if traj_result.get('lcia_calculated'):
                traj_score += 2
            if traj_result.get('two_systems_created'):
                traj_score += 2
            score += traj_score
            feedback.append(
                f"VLM trajectory: workflow={traj_result.get('workflow_started')}, "
                f"two_systems={traj_result.get('two_systems_created')}, "
                f"lcia={traj_result.get('lcia_calculated')}"
            )
        else:
            feedback.append("VLM trajectory check unavailable")
    else:
        feedback.append("VLM trajectory: insufficient frames or VLM unavailable")

    # VLM Check: final frame (5 pts)
    if vlm_ok and final_frame:
        final_result = _vlm_query(query_vlm, FINAL_FRAME_PROMPT, image=final_frame)
        if final_result:
            final_score = 0
            if final_result.get('results_visible'):
                final_score += 2
            if final_result.get('comparison_data'):
                final_score += 2
            if final_result.get('gwp_shown'):
                final_score += 1
            score += final_score
            feedback.append(
                f"VLM final: results={final_result.get('results_visible')}, "
                f"comparison={final_result.get('comparison_data')}"
            )
        else:
            feedback.append("VLM final frame check unavailable")
    else:
        feedback.append("VLM final: no frame or VLM unavailable")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= 60

    # GATE: Must have at least one product system and some exported file to pass
    if passed and ps_count == 0 and not has_file:
        passed = False
        feedback.append("GATE FAIL: No product systems and no exported file")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "debug": {
            "ps_count": ps_count,
            "impact_cat_count": result.get('impact_cat_count', 0),
            "file_size": result.get('comparison_file_size', 0),
            "has_glass": has_glass,
            "has_aluminum": has_alum,
        }
    }
