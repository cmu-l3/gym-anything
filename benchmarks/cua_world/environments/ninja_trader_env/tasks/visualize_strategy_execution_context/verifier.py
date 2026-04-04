#!/usr/bin/env python3
"""
Verifier for visualize_strategy_execution_context task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_visualize_strategy_execution_context(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Ran the backtest (implied by producing the specific chart output).
    2. Exported the chart image to the correct path.
    3. The image contains the Strategy Analyzer context (trades + SMA).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path')
    
    # 1. Parse JSON Result from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # The export script writes to a fixed path in the container
        copy_from_env("C:\\workspace\\tasks\\visualize_strategy_execution_context\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve Exported Image for VLM Analysis
    # We copy the image produced by the agent to the host for verification
    temp_image = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    image_retrieved = False
    try:
        if result_data.get('output_exists'):
            copy_from_env(expected_path, temp_image.name)
            image_retrieved = True
    except Exception as e:
        logger.warning(f"Could not copy exported image: {e}")
    
    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Timestamp (Anti-Gaming) (30 pts)
    if result_data.get('output_exists'):
        if result_data.get('file_created_during_task'):
            score += 30
            feedback_parts.append("Image exported successfully during task (+30)")
        else:
            score += 10
            feedback_parts.append("Image exists but timestamp predates task start (+10)")
    else:
        feedback_parts.append("Output image not found (0)")
        # Fail early if no image
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Image Content Validation via VLM (70 pts)
    if image_retrieved:
        vlm_prompt = (
            "Analyze this chart image produced by NinjaTrader 8. "
            "1. Does it show a financial chart (candlesticks or bars)?"
            "2. Are there execution markers visible (small arrows or triangles usually indicating buy/sell points)?"
            "3. Is there a continuous line indicator overlaying the price (like a Moving Average)?"
            "4. Does the context look like a Strategy Analyzer result (often has a specific toolbar or cleaner look than a main chart)?"
            "Respond in JSON: {'is_chart': bool, 'has_trades': bool, 'has_indicator': bool}"
        )
        
        try:
            # We use the explicitly exported image for verification as it's the direct artifact
            vlm_response = query_vlm(prompt=vlm_prompt, image=temp_image.name)
            
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                
                # Check Chart
                if parsed.get('is_chart'):
                    score += 10
                    feedback_parts.append("Valid chart content (+10)")
                
                # Check Trades (Evidence of Backtest)
                if parsed.get('has_trades'):
                    score += 30
                    feedback_parts.append("Execution markers visible (Backtest confirmed) (+30)")
                else:
                    feedback_parts.append("No execution markers found - backtest may not have run or produced trades")

                # Check Indicator (SMA)
                if parsed.get('has_indicator'):
                    score += 30
                    feedback_parts.append("SMA Indicator line visible (+30)")
                else:
                    feedback_parts.append("No indicator line found")
            else:
                feedback_parts.append("VLM analysis failed to parse image")
                # Fallback: if file size is reasonable, give partial credit
                if result_data.get('file_size_bytes', 0) > 20000:
                    score += 20
                    feedback_parts.append("File size indicates non-empty image (+20 fallback)")
                    
        except Exception as e:
            feedback_parts.append(f"VLM error: {e}")
    
    # Cleanup
    if os.path.exists(temp_image.name):
        os.unlink(temp_image.name)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }