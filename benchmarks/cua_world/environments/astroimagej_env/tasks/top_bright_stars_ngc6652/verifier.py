#!/usr/bin/env python3
"""
Verifier for Top Bright Stars in NGC 6652 task.

Scores out of 100 based on:
1. Catalog file creation & validity (20 pts)
2. Star position matching (15 + 12 + 18 = 45 pts)
3. Flux ordering logic (15 pts)
4. Flux values sanity check (5 pts)
5. VLM Trajectory (10 pts)
6. VLM Final visual (5 pts)
"""

import json
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)

def verify_top_bright_stars(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    metadata = task_info.get('metadata', {})
    tol_pixels = metadata.get('position_tolerance_pixels', 20)

    # 1. Load exported result
    result = {}
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # 2. Load ground truth
    gt = {}
    try:
        gt_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/bright_stars_ground_truth.json", gt_temp.name)
        with open(gt_temp.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(gt_temp.name):
            os.unlink(gt_temp.name)

    gt_stars = gt.get('top_5_stars', [])
    if len(gt_stars) < 5:
        return {"passed": False, "score": 0, "feedback": "Ground truth incomplete (setup issue)."}

    # 3. Assess Catalog File Existence
    if not result.get('catalog_exists'):
        feedback.append("❌ Catalog file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    if not result.get('catalog_created_during_task'):
        feedback.append("⚠️ Catalog file predates task start (gaming attempt?).")
    else:
        score += 10
        feedback.append("✅ Catalog file found and created during task.")

    # 4. Parse Catalog Content
    content = result.get('catalog_content', "").replace('|', '\n')
    parsed_stars = []
    
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#') or line.lower().startswith('rank'):
            continue
            
        parts = [p.strip() for p in line.replace(',', ' ').split() if p.strip()]
        try:
            nums = [float(p) for p in parts]
            if len(nums) >= 3:
                # If 4 columns: Rank, X, Y, Flux
                if len(nums) >= 4:
                    x, y, flux = nums[-3], nums[-2], nums[-1]
                else:
                    x, y, flux = nums[0], nums[1], nums[2]
                parsed_stars.append({'x': x, 'y': y, 'flux': flux})
        except ValueError:
            pass

    if len(parsed_stars) >= 5:
        score += 10
        feedback.append("✅ Parsed at least 5 numeric star entries.")
    else:
        score += len(parsed_stars) * 2
        feedback.append(f"⚠️ Parsed only {len(parsed_stars)} star entries from catalog.")

    # 5. Position Matching (Distance checking)
    matched_gt = set()
    pts_awarded_for_positions = 0
    
    # We will iterate through gt_stars (ranked 1 to 5) and try to find a match in parsed_stars
    # We don't enforce that the agent's rank exactly matches the GT rank for position matching,
    # just that the group of 5 brightest stars was identified.
    for i, gt_star in enumerate(gt_stars):
        best_dist = float('inf')
        best_match_idx = -1
        
        for j, p_star in enumerate(parsed_stars):
            dist = math.sqrt((gt_star['x'] - p_star['x'])**2 + (gt_star['y'] - p_star['y'])**2)
            if dist < best_dist:
                best_dist = dist
                best_match_idx = j
                
        if best_dist <= tol_pixels:
            if i == 0: # Star 1
                pts_awarded_for_positions += 15
                feedback.append(f"✅ Found match for Rank 1 star (dist={best_dist:.1f}px).")
            elif i == 1: # Star 2
                pts_awarded_for_positions += 12
                feedback.append(f"✅ Found match for Rank 2 star (dist={best_dist:.1f}px).")
            else: # Stars 3, 4, 5
                pts_awarded_for_positions += 6
                feedback.append(f"✅ Found match for Rank {i+1} star (dist={best_dist:.1f}px).")
        else:
            feedback.append(f"❌ Missed Rank {i+1} star (closest was {best_dist:.1f}px away).")
            
    score += pts_awarded_for_positions

    # 6. Check Flux Ordering & Values
    if len(parsed_stars) > 1:
        is_decreasing = True
        all_positive = True
        for i in range(len(parsed_stars)-1):
            if parsed_stars[i]['flux'] < parsed_stars[i+1]['flux']:
                is_decreasing = False
            if parsed_stars[i]['flux'] <= 0:
                all_positive = False
        if parsed_stars[-1]['flux'] <= 0:
            all_positive = False
            
        if is_decreasing:
            score += 15
            feedback.append("✅ Flux values correctly ordered descending.")
        else:
            feedback.append("❌ Flux values are not monotonically decreasing as requested.")
            
        # 7. Check magnitude of flux values against GT
        gt_flux_mean = sum(s['flux'] for s in gt_stars) / len(gt_stars)
        ag_flux_mean = sum(s['flux'] for s in parsed_stars) / len(parsed_stars)
        
        if all_positive and (gt_flux_mean * 0.01 <= ag_flux_mean <= gt_flux_mean * 100):
            score += 5
            feedback.append("✅ Flux values are positive and physically reasonable.")
        else:
            feedback.append("⚠️ Flux values seem outside expected physical ranges.")

    # 8. VLM Trajectory & Content Check
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            
            prompt = """Analyze these screenshots of an agent performing astronomy tasks.
            1. 'apertures_placed': Do any of the frames show multiple aperture circles (rings) placed on bright stars in the FITS image?
            2. 'table_visible': Does the final image show a Results or Measurements table?
            Return JSON: {"apertures_placed": true/false, "table_visible": true/false}"""
            
            images_to_send = frames + [final_img] if final_img else frames
            if images_to_send:
                vlm_res = query_vlm(prompt=prompt, images=images_to_send)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('apertures_placed', False):
                        score += 10
                        feedback.append("✅ VLM confirmed apertures placed during trajectory.")
                    else:
                        feedback.append("❌ VLM did not see aperture placement in trajectory.")
                        
                    if parsed.get('table_visible', False):
                        score += 5
                        feedback.append("✅ VLM confirmed results table visible.")
                else:
                    feedback.append("⚠️ VLM request failed.")
        except Exception as e:
            feedback.append(f"⚠️ VLM check error: {e}")
    else:
        feedback.append("⚠️ VLM function not provided, skipping visual checks.")

    # Final pass determination
    # Must have >= 60 points and found at least the top star
    passed = (score >= 60) and (pts_awarded_for_positions >= 15)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }