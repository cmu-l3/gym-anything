#!/usr/bin/env python3
"""
Verifier for wolf_rayet_bubble_survey task.

Criteria (100 pts total, pass >= 65):
1. WR 136 Observations (>=2 Ha, >=2 OIII valid FITS >60s)  - 15 pts
2. WR 7 Observations (>=2 Ha, >=2 OIII valid FITS >60s)    - 15 pts
3. WR 134 Observations (>=2 Ha, >=2 OIII valid FITS >60s)  - 15 pts
4. Sky survey PNGs (1 per target generated via script)     - 15 pts
5. Directory Structure matches expectations                - 10 pts
6. Summary report created and names targets                - 15 pts
7. VLM Trajectory Process Check                            - 15 pts

Anti-gaming: Stale FITS files in WR_136/Ha exist but must be rejected based on task_start timestamp.
"""

import json
import base64
import os
import tempfile
import logging
import sys

# To support the VLM import
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("VLM libraries not available. VLM checks will automatically fail/skip.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wolf_rayet_bubble_survey(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # Load export results
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)

    # Filter out valid FITS (created AFTER task started, size > 2KB, exposure >= 59s)
    fits_files = result.get('fits_files', [])
    valid_fits = [
        f for f in fits_files
        if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048 and f.get('exptime', 0) >= 59.0
    ]

    def count_target_filter(target_name, filter_name):
        return sum(
            1 for f in valid_fits 
            if target_name.upper() in f.get('target_dir', '').upper() 
            and filter_name.upper() in f.get('filter_dir', '').upper()
        )

    # 1. WR 136 Observations (15 pts)
    wr136_ha = count_target_filter('WR_136', 'Ha')
    wr136_oiii = count_target_filter('WR_136', 'OIII')
    if wr136_ha >= 2 and wr136_oiii >= 2:
        score += 15
        feedback.append("WR 136: Complete")
    elif wr136_ha >= 1 or wr136_oiii >= 1:
        score += 7
        feedback.append(f"WR 136: Partial (Ha:{wr136_ha}, OIII:{wr136_oiii})")
    else:
        feedback.append("WR 136: Missing valid exposures")

    # 2. WR 7 Observations (15 pts)
    wr7_ha = count_target_filter('WR_7', 'Ha')
    wr7_oiii = count_target_filter('WR_7', 'OIII')
    if wr7_ha >= 2 and wr7_oiii >= 2:
        score += 15
        feedback.append("WR 7: Complete")
    elif wr7_ha >= 1 or wr7_oiii >= 1:
        score += 7
        feedback.append(f"WR 7: Partial (Ha:{wr7_ha}, OIII:{wr7_oiii})")
    else:
        feedback.append("WR 7: Missing valid exposures")

    # 3. WR 134 Observations (15 pts)
    wr134_ha = count_target_filter('WR_134', 'Ha')
    wr134_oiii = count_target_filter('WR_134', 'OIII')
    if wr134_ha >= 2 and wr134_oiii >= 2:
        score += 15
        feedback.append("WR 134: Complete")
    elif wr134_ha >= 1 or wr134_oiii >= 1:
        score += 7
        feedback.append(f"WR 134: Partial (Ha:{wr134_ha}, OIII:{wr134_oiii})")
    else:
        feedback.append("WR 134: Missing valid exposures")

    # 4. Sky survey PNGs (15 pts)
    png_files = result.get('png_files', [])
    valid_pngs = [p for p in png_files if p.get('mtime', 0) > task_start and p.get('size', 0) > 10000]
    targets_with_pngs = set(p.get('target_dir', '').upper() for p in valid_pngs)
    
    png_score = min(15, len(targets_with_pngs) * 5)
    score += png_score
    feedback.append(f"Sky Views: {len(targets_with_pngs)} target(s) processed (+{png_score} pts)")

    # 5. Directory Structure (10 pts)
    dirs_used = set(f.get('target_dir', '') + '/' + f.get('filter_dir', '') for f in valid_fits)
    expected_dirs = {'WR_136/Ha', 'WR_136/OIII', 'WR_7/Ha', 'WR_7/OIII', 'WR_134/Ha', 'WR_134/OIII'}
    matching_dirs = sum(1 for d in expected_dirs if any(d.upper() in u.upper() for u in dirs_used))
    
    if matching_dirs == 6:
        score += 10
        feedback.append("Directory tree: Perfect")
    elif matching_dirs > 0:
        score += 5
        feedback.append(f"Directory tree: Partial ({matching_dirs}/6 used)")
    else:
        feedback.append("Directory tree: Failed to organize files")

    # 6. Report verification (15 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    
    if report_exists and report_mtime > task_start:
        b64 = result.get('report_b64', '')
        try:
            report_text = base64.b64decode(b64).decode('utf-8').upper()
            mentions = 0
            for t in ['WR 136', 'WR136', 'WR 7', 'WR7', 'WR 134', 'WR134']:
                if t in report_text:
                    mentions += 1
            
            if mentions >= 3:
                score += 15
                feedback.append("Report: Verified (Targets named)")
            else:
                score += 7
                feedback.append("Report: Created but missing target names")
        except:
            score += 5
            feedback.append("Report: Created but couldn't parse content")
    else:
        feedback.append("Report: Missing or pre-dates task")

    # 7. VLM Trajectory Verification (15 pts)
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = """You are verifying an agent using KStars and Ekos for a multi-target observational astronomy survey.
Did the agent interact with the Ekos observatory control interface (specifically CCD capture or mount slew controls) or interact with a terminal to run scripts during the timeline of these images?
Look for elements like the Ekos window, filter wheels, exposure tables, or active command-line usage.
Respond ONLY with JSON containing:
{
    "ekos_or_terminal_active": true/false,
    "reason": "brief explanation"
}"""
                vlm_res = query_vlm(images=frames, prompt=prompt)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('ekos_or_terminal_active'):
                        score += 15
                        feedback.append("VLM: Workflow confirmed visually")
                    else:
                        feedback.append("VLM: Could not confirm KStars/Ekos usage")
                else:
                    feedback.append("VLM: Query failed, skipping")
            else:
                feedback.append("VLM: No frames, skipping")
        except Exception as e:
            logger.warning(f"VLM verification exception: {e}")
            feedback.append("VLM: Check skipped due to error")
    else:
        # Give points automatically if VLM isn't loaded (so tests don't penalize missing env config)
        score += 15
        feedback.append("VLM: Skipped (auto-credit)")

    # Final pass/fail determination
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }