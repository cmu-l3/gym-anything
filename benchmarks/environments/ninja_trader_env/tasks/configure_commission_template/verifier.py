#!/usr/bin/env python3
"""
Verifier for configure_commission_template task.

Verifies:
1. Commission templates created correctly (XML parsing)
2. Backtest configuration in workspace
3. Anti-gaming (timestamps)
4. VLM verification of UI workflow
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_configure_commission_template(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    ib = result.get('ib_template', {})
    schwab = result.get('schwab_template', {})
    ws = result.get('workspace', {})

    # Criterion 1: IB Template (30 pts)
    if ib.get('found'):
        if ib.get('modified'):
            score += 10
            # Check rate (0.005)
            try:
                if float(ib.get('rate', 0)) == 0.005:
                    score += 10
                    feedback_parts.append("IB Rate correct")
                else:
                    feedback_parts.append(f"IB Rate mismatch ({ib.get('rate')})")
            except: pass
            
            # Check min (1.00)
            try:
                if float(ib.get('min', 0)) == 1.0:
                    score += 10
                    feedback_parts.append("IB Min correct")
                else:
                    feedback_parts.append(f"IB Min mismatch ({ib.get('min')})")
            except: pass
        else:
            feedback_parts.append("IB template found but stale (anti-gaming)")
    else:
        feedback_parts.append("IB template missing")

    # Criterion 2: Schwab Template (20 pts)
    if schwab.get('found'):
        if schwab.get('modified'):
            score += 10
            try:
                if float(schwab.get('rate', 0)) == 4.95:
                    score += 10
                    feedback_parts.append("Schwab Rate correct")
                else:
                    feedback_parts.append(f"Schwab Rate mismatch ({schwab.get('rate')})")
            except: pass
        else:
            feedback_parts.append("Schwab template found but stale")
    else:
        feedback_parts.append("Schwab template missing")

    # Criterion 3: Workspace/Strategy Config (30 pts)
    if ws.get('modified'):
        score += 10
        feedback_parts.append("Workspace saved")
        
        if ws.get('strategy_configured') and ws.get('instrument_correct'):
            score += 10
            feedback_parts.append("Strategy+Instrument correct")
        
        if ws.get('commission_applied'):
            score += 10
            feedback_parts.append("Commission linked to backtest")
    else:
        feedback_parts.append("Workspace not saved")

    # Criterion 4: VLM Verification (20 pts)
    # Check if agent actually interacted with Commission dialog and Backtest UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    prompt = """
    Analyze these screenshots of NinjaTrader interaction.
    1. Do you see the "Commission Template" or "Commissions" dialog open in any frame?
    2. Do you see the "Strategy Analyzer" window?
    3. In the final result, is there a backtest performance report visible?
    
    Answer JSON: {"commission_dialog_seen": bool, "strategy_analyzer_seen": bool, "backtest_results_seen": bool}
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
        parsed = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('commission_dialog_seen'): vlm_score += 5
        if parsed.get('strategy_analyzer_seen'): vlm_score += 5
        if parsed.get('backtest_results_seen'): vlm_score += 10
        
        score += vlm_score
        feedback_parts.append(f"VLM Score: {vlm_score}/20")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if we have strong programmatic evidence, give partial VLM credit
        if score >= 60:
            score += 10
            feedback_parts.append("VLM skipped (system error), +10 fallback")

    passed = score >= 60 and ib.get('found') and ib.get('modified')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }