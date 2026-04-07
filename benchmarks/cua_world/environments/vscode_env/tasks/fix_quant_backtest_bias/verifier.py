#!/usr/bin/env python3
"""
Verifier for the fix_quant_backtest_bias task.

Checks whether the agent fixed the 4 time-series logical errors in
backtest_engine.py using robust static analysis (Regex/AST evaluation).

Each fix is worth 20 points.
Trajectory VLM verification is worth 20 points.
Total 100 points. Pass threshold: 75 points.
"""

import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_quant_backtest(traj, env_info, task_info):
    """
    Verify the 4 time-series data manipulation bug fixes.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='quant_verify_')
    
    try:
        # 1. Read exported source code
        result_src = "/tmp/quant_backtest_result.json"
        local_result = os.path.join(temp_dir, "quant_backtest_result.json")

        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not access result file: {str(e)}"}

        if not os.path.exists(local_result):
            return {"passed": False, "score": 0, "feedback": "Result file not found"}

        with open(local_result, 'r') as f:
            file_contents = json.load(f)

        src = file_contents.get("backtest_engine_code", "")
        if not src:
            return {"passed": False, "score": 0, "feedback": "backtest_engine.py is missing or empty"}

        score = 0
        feedback = []
        criteria_passed = 0

        # ==========================================
        # Bug 1: Future Leakage in Imputation
        # ==========================================
        # Bug: .fillna(self.df['Close'].mean())
        # Fix: .fillna(method='ffill') or .ffill()
        still_has_mean = bool(re.search(r'fillna\(.*\.mean\(\)\s*\)', src))
        has_ffill = bool(re.search(r'fillna\(.*method\s*=\s*[\'"]ffill[\'"]\)', src) or re.search(r'\.ffill\(\)', src) or re.search(r'fillna\(.*method\s*=\s*[\'"]pad[\'"]\)', src))
        
        if has_ffill and not still_has_mean:
            score += 20
            criteria_passed += 1
            feedback.append("✅ Imputation: Correctly uses forward fill instead of global mean.")
        else:
            feedback.append("❌ Imputation: Still uses mean or missing correct forward fill.")

        # ==========================================
        # Bug 2: Signal Lookahead Bias
        # ==========================================
        # Bug: self.df['Strategy_Return'] = self.df['Position'] * self.df['Daily_Return']
        # Fix: self.df['Strategy_Return'] = self.df['Position'].shift(1) * self.df['Daily_Return']
        # OR   self.df['Strategy_Return'] = self.df['Position'] * self.df['Daily_Return'].shift(-1)
        still_unlagged = bool(re.search(r'Strategy_Return.*=\s*self\.df\[[\'"]Position[\'"]\]\s*\*\s*self\.df\[[\'"]Daily_Return[\'"]\]', src))
        has_shift_pos = bool(re.search(r'Position[\'"]\]\.shift\(1\)', src))
        has_shift_ret = bool(re.search(r'Daily_Return[\'"]\]\.shift\(-1\)', src))
        
        if (has_shift_pos or has_shift_ret) and not still_unlagged:
            score += 20
            criteria_passed += 1
            feedback.append("✅ Lookahead Bias: Correctly shifted positions to prevent leaking future returns.")
        else:
            feedback.append("❌ Lookahead Bias: Returns are still multiplied un-lagged, leaking tomorrow's return to today.")

        # ==========================================
        # Bug 3: Transaction Cost Overcharging
        # ==========================================
        # Bug: (self.df['Position'].abs() > 0).astype(int)
        # Fix: self.df['Position'].diff().abs() or self.df['Position'] != self.df['Position'].shift(1)
        still_daily_cost = bool(re.search(r'Position[\'"]\]\.abs\(\)\s*>\s*0', src) or re.search(r'Position[\'"]\]\s*!=\s*0', src))
        has_diff = bool(re.search(r'Position[\'"]\]\.diff\(\)', src))
        has_shift_compare = bool(re.search(r'Position[\'"]\]\s*!=\s*self\.df\[[\'"]Position[\'"]\]\.shift\(1\)', src))
        
        if (has_diff or has_shift_compare) and not still_daily_cost:
            score += 20
            criteria_passed += 1
            feedback.append("✅ Transaction Costs: Costs only deducted on position changes.")
        else:
            feedback.append("❌ Transaction Costs: Still charging costs on holding periods rather than changes.")

        # ==========================================
        # Bug 4: Global Max Drawdown
        # ==========================================
        # Bug: global_peak = self.df['Cumulative_Return'].max()
        # Fix: rolling_peak = self.df['Cumulative_Return'].cummax()
        still_global_max = bool(re.search(r'Cumulative_Return[\'"]\]\.max\(\)', src))
        has_cummax = bool(re.search(r'Cumulative_Return[\'"]\]\.cummax\(\)', src))
        
        if has_cummax and not still_global_max:
            score += 20
            criteria_passed += 1
            feedback.append("✅ Max Drawdown: Correctly utilizes a rolling cummax() instead of global max().")
        else:
            feedback.append("❌ Max Drawdown: Still calculates drawdown against an unachieved future global maximum.")

        # ==========================================
        # VLM Trajectory Verification (Anti-gaming)
        # ==========================================
        if query_vlm:
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=4)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                vlm_prompt = (
                    "You are verifying a coding task in VS Code.\n"
                    "Did the agent actively edit python files (specifically related to pandas/financial backtesting) "
                    "in the code editor? Look for changes to functions like impute_data, calculate_returns, apply_costs, calculate_drawdown.\n"
                    "Reply ONLY in JSON: {\"edited_code\": true/false}"
                )
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=images)
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("edited_code", False):
                    score += 20
                    feedback.append("✅ VLM: Verified trajectory shows active code editing in VS Code.")
                else:
                    feedback.append("❌ VLM: Trajectory does not clearly show code being edited in the editor.")
            except Exception as e:
                logger.warning(f"VLM verification skipped or failed: {e}")
                # Grant points if programmatic checks passed to prevent failure from VLM timeout
                if criteria_passed >= 2:
                    score += 20
                    feedback.append("⚠️ VLM skipped but programmatic checks passed.")
        else:
            # If VLM is not available, scale the score so max is 100
            score = int((score / 80.0) * 100)
            feedback.append("⚠️ VLM verification unavailable. Scaling programmatic score.")

        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)