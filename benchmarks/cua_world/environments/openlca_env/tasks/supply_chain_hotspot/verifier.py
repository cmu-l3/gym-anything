#!/usr/bin/env python3
"""
Verifier for Supply Chain Hotspot Analysis task.

The agent must:
1. Import USLCI database and LCIA methods
2. Find cement/concrete process in USLCI and build a product system (4+ upstream links)
3. Run LCIA to get GWP
4. Perform process contribution analysis (which upstream processes drive GWP)
5. Export contribution breakdown to ~/LCA_Results/hotspot_analysis.csv

Scoring (100 points total):
  Programmatic:
    - (15 pts) Database imported (> 15MB)
    - (10 pts) LCIA methods imported
    - (20 pts) Product system created (ps_count >= 1)
    - (20 pts) Hotspot analysis file exported (size > 200 bytes)
    - (20 pts) File content: cement/concrete domain + percentage + process data
    - (5 pts)  GWP data present in file
  VLM:
    - (5 pts)  Trajectory shows contribution analysis workflow
    - (5 pts)  Final shows hotspot/contribution view

Pass threshold: 60 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are reviewing screenshots of an agent using openLCA to perform a supply chain hotspot analysis for cement or concrete production.

Expected workflow:
1. Import USLCI database and LCIA methods
2. Find cement or concrete process in USLCI database
3. Create product system expanding upstream supply chain (limestone, energy, transport, etc.)
4. Run LCIA calculation
5. Navigate to "Process contributions" or "Contribution tree" view showing upstream processes with percentages
6. Export the contribution breakdown to CSV

Key visual indicators of hotspot/contribution analysis:
- A tree view or table showing multiple upstream processes with percentage contributions
- A Sankey diagram showing material/energy flows with process contributions
- A "Contribution analysis" or "Process contributions" panel in the results view
- Percentages next to process names in the LCIA results

Assess:
- PRODUCT_SYSTEM_VISIBLE: Evidence of a product system being built
- LCIA_CALCULATED: Evidence of LCIA calculation results
- CONTRIBUTION_VIEW: Evidence of process contribution analysis being visible
- EXPORT_DONE: Evidence of data being exported

Return JSON:
{
  "product_system_visible": true/false,
  "lcia_calculated": true/false,
  "contribution_view": true/false,
  "export_done": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "brief description"
}"""

FINAL_FRAME_PROMPT = """This is the final screenshot from an agent that should have completed a supply chain hotspot analysis in openLCA for cement/concrete production.

A successful final state shows one of:
- A process contribution table showing upstream process names and their % share of GWP
- A Sankey diagram showing flows through the supply chain with contribution percentages
- A CSV file or spreadsheet open showing process names and percentage values
- openLCA contribution tree/analysis view with cement-related processes visible

Check:
- CONTRIBUTION_DATA: Are process names with percentage contributions visible?
- CEMENT_CONTEXT: Is there evidence related to cement, concrete, clinker, or limestone?
- PERCENTAGES_VISIBLE: Can you see percentage values (e.g., "45%", "23.5%")?
- DATA_EXPORTED: Is there evidence that a CSV/spreadsheet was saved?

Return JSON:
{
  "contribution_data": true/false,
  "cement_context": true/false,
  "percentages_visible": true/false,
  "data_exported": true/false,
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


def verify_supply_chain_hotspot(traj, env_info, task_info):
    """Verify supply chain hotspot analysis was completed."""
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

    # ── Criterion 2: LCIA methods imported (10 pts) ───────────────────────────
    lcia_ok = result.get('impact_cat_count', 0) > 0
    if lcia_ok:
        score += 10
        subscores['lcia'] = True
        feedback.append(f"LCIA methods imported ({result.get('impact_cat_count')} categories)")
    else:
        subscores['lcia'] = False
        feedback.append("LCIA methods not imported")

    # ── Criterion 3: Product system created (20 pts) ──────────────────────────
    ps_count = result.get('ps_count', 0)
    if ps_count >= 1:
        score += 20
        subscores['product_system'] = True
        feedback.append(f"Product system created (count={ps_count})")
    else:
        subscores['product_system'] = False
        feedback.append("No product system found in database")

    # ── Criterion 4: Hotspot analysis file exported (20 pts) ──────────────────
    has_file = (
        result.get('hotspot_file') and
        result.get('hotspot_file_size', 0) > 200
    )
    if has_file:
        score += 20
        subscores['file_exported'] = True
        feedback.append(
            f"Hotspot file exported ({result.get('hotspot_file_size')} bytes): "
            f"{os.path.basename(result.get('hotspot_file', ''))}"
        )
    elif result.get('current_result_count', 0) > result.get('initial_result_count', 0):
        score += 8
        subscores['file_exported'] = False
        feedback.append("New file found but too small or not recognized")
    else:
        subscores['file_exported'] = False
        feedback.append("No hotspot analysis file exported to ~/LCA_Results/")

    # ── Criterion 5: File content quality (20 pts) ────────────────────────────
    has_cement = result.get('has_cement_keyword', 0) == 1
    has_pct = result.get('has_percent_keyword', 0) == 1
    has_proc = result.get('has_process_keyword', 0) == 1
    row_count = result.get('hotspot_row_count', 0)

    content_score = 0
    content_parts = []
    if has_cement:
        content_score += 7
        content_parts.append("cement/concrete domain confirmed")
    if has_pct:
        content_score += 7
        content_parts.append("percentage contributions present")
    if has_proc:
        content_score += 6
        content_parts.append("process/contribution terminology present")

    if content_score > 0:
        score += content_score
        subscores['content_quality'] = content_score >= 13
        feedback.append(f"Content: {', '.join(content_parts)} (rows: {row_count})")
    else:
        subscores['content_quality'] = False
        if has_file:
            feedback.append("File exported but lacks cement + contribution content")

    # ── Criterion 6: GWP data in file (5 pts) ────────────────────────────────
    if result.get('has_gwp_keyword', 0) == 1:
        score += 5
        subscores['gwp_in_file'] = True
        feedback.append("GWP data present in file")
    else:
        subscores['gwp_in_file'] = False

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
            if traj_result.get('contribution_view'):
                traj_pts += 3
            if traj_result.get('lcia_calculated'):
                traj_pts += 2
            score += traj_pts
            feedback.append(
                f"VLM trajectory: contribution={traj_result.get('contribution_view')}, "
                f"lcia={traj_result.get('lcia_calculated')}"
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
            if final_result.get('contribution_data'):
                final_pts += 3
            if final_result.get('percentages_visible'):
                final_pts += 2
            score += final_pts
            feedback.append(
                f"VLM final: contribution={final_result.get('contribution_data')}, "
                f"percentages={final_result.get('percentages_visible')}"
            )
        else:
            feedback.append("VLM final unavailable")
    else:
        feedback.append("VLM final: no frame")

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "debug": {
            "ps_count": ps_count,
            "hotspot_file_size": result.get('hotspot_file_size', 0),
            "has_cement": has_cement,
            "has_pct": has_pct,
        }
    }
