#!/usr/bin/env python3
"""
Verifier for Scenario Electricity Comparison task.

The agent must:
1. Import USLCI database and LCIA methods
2. Build product systems for BOTH coal and natural gas electricity
3. Run LCIA for both (GWP + Acidification)
4. Calculate % GWP reduction from coal → gas
5. Export comparison to ~/LCA_Results/electricity_scenarios.csv

Scoring (100 points total):
  Programmatic:
    - (15 pts) Database imported (> 15MB)
    - (10 pts) LCIA methods imported
    - (25 pts) TWO product systems in DB (ps_count >= 2)
    - (20 pts) Scenario comparison file exported (size > 200 bytes)
    - (20 pts) File content: coal + gas + GWP + acidification + % difference
  VLM:
    - (5 pts)  Trajectory shows two-scenario workflow
    - (5 pts)  Final shows comparison data or exported file

Pass threshold: 60 points.
GATE: ps_count >= 2 is required for full score on criterion 3.
      If ps_count == 1, the task only partially succeeds.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are reviewing screenshots of an agent using openLCA to compare the environmental impact of two electricity generation scenarios: coal-fired power vs. natural gas power.

Expected workflow:
1. Import USLCI database and LCIA methods into openLCA
2. Find coal electricity process in USLCI and create first product system
3. Run LCIA for coal system (capture GWP and Acidification values)
4. Find natural gas electricity process and create second product system
5. Run LCIA for natural gas system (same method, same categories)
6. Compare the results and calculate percentage reduction in GWP
7. Export comparison data to a CSV file

Assess:
- TWO_SYSTEMS: Evidence that two separate product systems were created
- BOTH_CALCULATED: Evidence that LCIA was run for BOTH scenarios
- COMPARISON_DONE: Evidence of comparison between coal and gas results
- EXPORT_DONE: Evidence of file export

Return JSON:
{
  "two_systems": true/false,
  "both_calculated": true/false,
  "comparison_done": true/false,
  "export_done": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "brief description"
}"""

FINAL_FRAME_PROMPT = """This is the final screenshot from an agent comparing coal vs. natural gas electricity LCA results in openLCA.

A successful final state shows:
- A CSV or spreadsheet with two rows/columns representing coal electricity and natural gas electricity
- GWP and Acidification values for both scenarios
- A calculated percentage reduction/difference between them
- OR: openLCA with two results views showing both scenarios' impact scores

Check:
- TWO_SCENARIOS_VISIBLE: Can you see data for BOTH coal and natural gas?
- IMPACT_VALUES: Are numeric environmental impact values visible?
- COMPARISON_DATA: Is there a comparison table or % difference shown?
- FILE_SAVED: Is there evidence the data was exported to a file?

Return JSON:
{
  "two_scenarios_visible": true/false,
  "impact_values": true/false,
  "comparison_data": true/false,
  "file_saved": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "description"
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


def verify_scenario_electricity_comparison(traj, env_info, task_info):
    """Verify electricity scenario comparison was completed."""
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

    # ── Criterion 3: TWO product systems (25 pts) ─────────────────────────────
    ps_count = result.get('ps_count', 0)
    if ps_count >= 2:
        score += 25
        subscores['two_scenarios'] = True
        feedback.append(f"Two product systems created (coal + gas): ps_count={ps_count}")
    elif ps_count == 1:
        score += 10
        subscores['two_scenarios'] = False
        feedback.append("Only ONE product system — need coal AND natural gas scenarios")
    else:
        subscores['two_scenarios'] = False
        feedback.append("No product systems found")

    # ── Criterion 4: Scenario comparison file exported (20 pts) ──────────────
    has_file = (
        result.get('scenario_file') and
        result.get('scenario_file_size', 0) > 200
    )
    if has_file:
        score += 20
        subscores['file_exported'] = True
        feedback.append(
            f"Scenario file exported ({result.get('scenario_file_size')} bytes): "
            f"{os.path.basename(result.get('scenario_file', ''))}"
        )
    elif result.get('current_result_count', 0) > result.get('initial_result_count', 0):
        score += 8
        subscores['file_exported'] = False
        feedback.append("New file found but unrecognized")
    else:
        subscores['file_exported'] = False
        feedback.append("No scenario comparison file exported")

    # ── Criterion 5: File content quality (20 pts) ────────────────────────────
    has_coal = result.get('has_coal_keyword', 0) == 1
    has_gas = result.get('has_gas_keyword', 0) == 1
    has_gwp = result.get('has_gwp_keyword', 0) == 1
    has_acid = result.get('has_acidification_keyword', 0) == 1
    has_pct = result.get('has_percent_keyword', 0) == 1

    content_score = 0
    content_parts = []
    if has_coal:
        content_score += 4
        content_parts.append("coal scenario")
    if has_gas:
        content_score += 4
        content_parts.append("natural gas scenario")
    if has_gwp:
        content_score += 4
        content_parts.append("GWP data")
    if has_acid:
        content_score += 4
        content_parts.append("acidification data")
    if has_pct:
        content_score += 4
        content_parts.append("% difference")

    if content_score > 0:
        score += content_score
        subscores['content'] = content_score >= 12
        feedback.append(f"Content quality: {', '.join(content_parts)} ({content_score}/20 pts)")
    else:
        subscores['content'] = False
        if has_file:
            feedback.append("File exported but lacks coal/gas comparison content")

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
            if traj_result.get('two_systems'):
                traj_pts += 3
            if traj_result.get('both_calculated'):
                traj_pts += 2
            score += traj_pts
            feedback.append(
                f"VLM trajectory: two_systems={traj_result.get('two_systems')}, "
                f"both_calculated={traj_result.get('both_calculated')}"
            )
        else:
            feedback.append("VLM trajectory unavailable")
    else:
        feedback.append("VLM trajectory: insufficient data")

    # VLM: final (5 pts)
    if vlm_ok and final_frame:
        final_result = _vlm_query(query_vlm, FINAL_FRAME_PROMPT, image=final_frame)
        if final_result:
            final_pts = 0
            if final_result.get('two_scenarios_visible'):
                final_pts += 3
            if final_result.get('comparison_data'):
                final_pts += 2
            score += final_pts
            feedback.append(
                f"VLM final: two_scenarios={final_result.get('two_scenarios_visible')}, "
                f"comparison={final_result.get('comparison_data')}"
            )
        else:
            feedback.append("VLM final unavailable")
    else:
        feedback.append("VLM final: no frame")

    # GATE: Both scenarios required for passing (prevents one-scenario gaming)
    passed = score >= 60
    if passed and ps_count < 2 and score < 70:
        # Only one scenario built — shouldn't pass unless compensated by VLM
        passed = False
        feedback.append("GATE: Both coal and natural gas scenarios required to pass")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "debug": {
            "ps_count": ps_count,
            "has_coal": has_coal,
            "has_gas": has_gas,
            "file_size": result.get('scenario_file_size', 0),
        }
    }
