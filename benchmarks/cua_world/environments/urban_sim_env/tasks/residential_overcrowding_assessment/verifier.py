#!/usr/bin/env python3
"""Verifier for residential_overcrowding_assessment task."""

import os
import json
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_residential_overcrowding_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    gt = {}
    res = {}
    
    # 1. Retrieve GT and Agent Result Data
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp_gt:
        try:
            copy_from_env("/tmp/overcrowding_ground_truth.json", tmp_gt.name)
            with open(tmp_gt.name, 'r') as f:
                gt = json.load(f)
        except Exception as e:
            feedback.append(f"GT load failed: {e}")
            
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp_res:
        try:
            copy_from_env("/tmp/task_result.json", tmp_res.name)
            with open(tmp_res.name, 'r') as f:
                res = json.load(f)
        except Exception as e:
            feedback.append(f"Result load failed: {e}")

    # Cleanup temp files
    try:
        os.unlink(tmp_gt.name)
        os.unlink(tmp_res.name)
    except OSError:
        pass

    if not gt or not res:
        return {"passed": False, "score": 0, "feedback": "Failed to load verification files."}

    # 2. Check CSV Basics (10 pts)
    csv_info = res.get('csv', {})
    if csv_info.get('exists') and csv_info.get('modified'):
        cols = [c.lower() for c in csv_info.get('columns', [])]
        expected = ['zone_id', 'total_persons', 'total_residential_units', 'persons_per_unit', 'pct_overcrowded_buildings', 'overcrowding_risk_index']
        missing = [c for c in expected if c not in cols]
        if not missing:
            score += 10
            feedback.append("CSV basics passed (+10)")
        else:
            score += 5
            feedback.append(f"CSV partial match, missing: {missing} (+5)")
    else:
        feedback.append("CSV not found or not created during task")

    # 3. Zone coverage (10 pts)
    agent_rows = csv_info.get('rows', 0)
    gt_rows = gt.get('num_zones', 1)
    if agent_rows >= gt_rows * 0.8:
        score += 10
        feedback.append(f"Zone coverage sufficient: {agent_rows}/{gt_rows} (+10)")
    elif agent_rows >= gt_rows * 0.4:
        score += 5
        feedback.append(f"Zone coverage partial: {agent_rows}/{gt_rows} (+5)")

    # 4. Accuracy checks against pre-computed Ground Truth (40 pts)
    agent_data = csv_info.get('data_sample', {})
    gt_sample = gt.get('sample_zones', {})
    
    ppu_matches = 0
    valid_pct = 0
    valid_risk = 0
    risk_max = 0
    checked = 0

    for zid, gt_vals in gt_sample.items():
        # Handle cases where agent exports floats for IDs (e.g. 1.0)
        agent_row = agent_data.get(zid, agent_data.get(zid + ".0"))
        if agent_row:
            checked += 1
            try:
                # Check PPU metric accuracy
                agent_ppu = float(agent_row.get('persons_per_unit', agent_row.get('PERSONS_PER_UNIT', 0)))
                gt_ppu = gt_vals['persons_per_unit']
                if gt_ppu > 0 and abs(agent_ppu - gt_ppu) / gt_ppu <= 0.15:
                    ppu_matches += 1
                    
                # Check percentage valid
                agent_pct = float(agent_row.get('pct_overcrowded_buildings', 0))
                if 0 <= agent_pct <= 100:
                    valid_pct += 1
                    
                # Check min-max indexing
                agent_risk = float(agent_row.get('overcrowding_risk_index', 0))
                if agent_risk > risk_max:
                    risk_max = agent_risk
                if -1 <= agent_risk <= 101:
                    valid_risk += 1
            except (ValueError, TypeError):
                pass

    if checked > 0:
        # PPU accuracy (20 pts)
        ppu_score = int(20 * (ppu_matches / checked))
        score += ppu_score
        feedback.append(f"PPU accuracy: {ppu_score}/20")
        
        # Percentage Overcrowded bounds (10 pts)
        pct_score = int(10 * (valid_pct / checked))
        score += pct_score
        feedback.append(f"Pct Overcrowded validity: {pct_score}/10")
        
        # Risk index normalization (10 pts)
        if valid_risk > checked * 0.8 and risk_max > 50:
            score += 10
            feedback.append("Risk index normalized appropriately (+10)")
        elif valid_risk > 0:
            score += 5
            feedback.append("Risk index partially valid (+5)")

    # 5. Notebook validation (10 pts)
    nb_info = res.get('notebook', {})
    if nb_info.get('exists') and nb_info.get('modified') and nb_info.get('num_exec', 0) >= 3:
        pats = nb_info.get('patterns', {})
        if pats.get('has_hdf') and pats.get('has_merge') and pats.get('has_groupby'):
            score += 10
            feedback.append("Notebook executed with required code structures (+10)")
        else:
            score += 5
            feedback.append("Notebook executed but missing some target code patterns (+5)")

    # 6. Plot validation (10 pts)
    plot_info = res.get('plot', {})
    if plot_info.get('exists') and plot_info.get('modified'):
        if plot_info.get('size_kb', 0) > 5:
            score += 10
            feedback.append("Plot created successfully (+10)")
        else:
            score += 5
            feedback.append("Plot created but might be corrupt or tiny (+5)")

    # 7. VLM Trajectory Verification (20 pts)
    vlm_score = 0
    try:
        # Resolve query_vlm correctly
        query_vlm = env_info.get('query_vlm')
        if not query_vlm:
            from gym_anything.vlm import query_vlm
            
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """Analyze these trajectory screenshots from an agent's desktop working in Jupyter Lab.
        Assess the following requirements:
        1. Is the agent actively writing or executing Python code in a Jupyter notebook?
        2. Is there a bar chart visible in the notebook output?
        3. Is there evidence of data analysis taking place (e.g. dataframes, pandas operations, numeric outputs)?
        Respond in JSON strictly formatted as: {"writing_code": true/false, "chart_visible": true/false, "data_analysis": true/false}"""
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('writing_code'): vlm_score += 10
            if parsed.get('chart_visible'): vlm_score += 5
            if parsed.get('data_analysis'): vlm_score += 5
            feedback.append(f"VLM verified trajectory progression (+{vlm_score})")
        else:
            feedback.append("VLM verification query returned unsuccessfully.")
    except Exception as e:
        feedback.append(f"VLM error: {e}")
        pass

    score += vlm_score

    # A pass requires at least 60 total score and successful CSV generation
    passed = score >= 60 and csv_info.get('exists', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }