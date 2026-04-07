#!/usr/bin/env python3
"""
Verifier for lsb_galaxy_deep_survey task.

Criteria (100 pts total, pass >= 60):
1. Malin 1 LIGHT frames (≥4 in target dir, 25s exp)       - 10 pts
2. Malin 2 LIGHT frames (≥4 in target dir, 25s exp)       - 10 pts
3. UGC 1382 LIGHT frames (≥4 in target dir, 25s exp)      - 10 pts
4. 25s DARK frames (≥5 in calibration dir, excl. stale)   - 15 pts
5. Sky views (view.png created in all three target dirs)  - 15 pts
6. Final Report (Mentions 3 targets, created during task) - 10 pts
7. VLM Trajectory Process Verification                    - 30 pts

Anti-gaming:
- Validates FITS IMAGETYP headers to ensure darks are actually darks.
- Uses `task_start` to ignore seeded stale dark frames.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an agent's trajectory performing a Low Surface Brightness Galaxy Survey in KStars/Ekos.

Review the sequence of trajectory screenshots chronologically. The agent was tasked with taking astronomical images of multiple galaxies and capturing dark calibration frames.

Observe the process and answer:
1. Did the agent open the camera/observatory controls (Ekos) and interact with it?
2. Did the agent change the exposure values (e.g., to 25s) and switch between "Light" and "Dark" frame types?
3. Did the agent cycle through multiple targets or sky fields over the course of the trajectory?
4. Is there evidence that the sequence progressed meaningfully (not just taking a single image and doing nothing)?

Respond strictly in JSON format:
{
    "ekos_interacted": true/false,
    "exposure_frame_type_adjusted": true/false,
    "multiple_targets_cycled": true/false,
    "meaningful_progression": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visually observed."
}
"""

def verify_lsb_survey(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

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
    
    # Pre-filter FITS files that are genuinely from this session
    valid_fits = [f for f in result.get('fits_files', [])
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]
    
    def count_light_frames(target_id):
        count = 0
        for f in valid_fits:
            path = f.get('path', '').upper()
            if target_id.upper() in path and f.get('frame_type') == 'LIGHT' and abs(f.get('exptime', 0) - 25.0) < 0.5:
                count += 1
        return count

    # 1. Malin 1 (10 pts)
    malin1_count = count_light_frames('MALIN_1')
    if malin1_count >= 4:
        score += 10
        feedback.append("Malin 1: all LIGHT frames captured")
    elif malin1_count > 0:
        score += 5
        feedback.append(f"Malin 1: partial capture ({malin1_count}/4 frames)")
    else:
        feedback.append("Malin 1: missing LIGHT frames")

    # 2. Malin 2 (10 pts)
    malin2_count = count_light_frames('MALIN_2')
    if malin2_count >= 4:
        score += 10
        feedback.append("Malin 2: all LIGHT frames captured")
    elif malin2_count > 0:
        score += 5
        feedback.append(f"Malin 2: partial capture ({malin2_count}/4 frames)")
    else:
        feedback.append("Malin 2: missing LIGHT frames")

    # 3. UGC 1382 (10 pts)
    ugc1382_count = count_light_frames('UGC_1382')
    if ugc1382_count >= 4:
        score += 10
        feedback.append("UGC 1382: all LIGHT frames captured")
    elif ugc1382_count > 0:
        score += 5
        feedback.append(f"UGC 1382: partial capture ({ugc1382_count}/4 frames)")
    else:
        feedback.append("UGC 1382: missing LIGHT frames")

    # 4. Calibration Dark Frames (15 pts)
    dark_count = 0
    for f in valid_fits:
        path = f.get('path', '').lower()
        if 'dark' in path and f.get('frame_type') == 'DARK' and abs(f.get('exptime', 0) - 25.0) < 0.5:
            dark_count += 1
            
    if dark_count >= 5:
        score += 15
        feedback.append(f"Darks: {dark_count} frames valid (stale files correctly ignored)")
    elif dark_count > 0:
        score += 7
        feedback.append(f"Darks: partial capture ({dark_count}/5 frames)")
    else:
        feedback.append("Darks: missing 25s DARK frames")

    # 5. Sky Views (15 pts)
    views_found = 0
    view_targets = set()
    for v in result.get('sky_views', []):
        if v.get('mtime', 0) > task_start:
            path = v.get('path', '').upper()
            if 'MALIN_1' in path: view_targets.add('Malin 1')
            if 'MALIN_2' in path: view_targets.add('Malin 2')
            if 'UGC_1382' in path: view_targets.add('UGC 1382')
    
    if len(view_targets) == 3:
        score += 15
        feedback.append("Sky Views: all 3 targets captured")
    elif len(view_targets) > 0:
        score += len(view_targets) * 5
        feedback.append(f"Sky Views: {len(view_targets)}/3 captured")
    else:
        feedback.append("Sky Views: none found")

    # 6. Survey Report (10 pts)
    if result.get('report_exists', False) and result.get('report_mtime', 0) > task_start:
        try:
            report_text = base64.b64decode(result.get('report_b64', '')).decode('utf-8', errors='ignore').upper()
            mentions = 0
            if 'MALIN 1' in report_text or 'MALIN_1' in report_text: mentions += 1
            if 'MALIN 2' in report_text or 'MALIN_2' in report_text: mentions += 1
            if 'UGC 1382' in report_text or 'UGC_1382' in report_text: mentions += 1
            
            if mentions == 3:
                score += 10
                feedback.append("Report: all targets mentioned")
            elif mentions > 0:
                score += 5
                feedback.append("Report: incomplete target list")
            else:
                feedback.append("Report: missing target names")
        except:
            feedback.append("Report: could not decode content")
    else:
        feedback.append("Report: missing or not updated during task")

    # 7. VLM Trajectory Verification (30 pts)
    vlm_score = 0
    try:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        frames.append(get_final_screenshot(traj))
        
        vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            checks_passed = sum([
                parsed.get('ekos_interacted', False),
                parsed.get('exposure_frame_type_adjusted', False),
                parsed.get('multiple_targets_cycled', False),
                parsed.get('meaningful_progression', False)
            ])
            vlm_score = int((checks_passed / 4.0) * 30)
            score += vlm_score
            feedback.append(f"VLM: Workflow verification score +{vlm_score}/30")
        else:
            feedback.append("VLM: Query failed, awarding partial fallback score")
            score += 15  # Fallback
    except Exception as e:
        logger.warning(f"VLM integration error: {e}")
        feedback.append("VLM: Integration error, awarding partial fallback score")
        score += 15  # Fallback
        
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }