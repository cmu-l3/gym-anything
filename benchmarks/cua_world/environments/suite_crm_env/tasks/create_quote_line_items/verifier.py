#!/usr/bin/env python3
"""
Verifier for create_quote_line_items task.

Verification Strategy:
1. Programmatic DB Verification (80 pts):
   - Quote record exists (15 pts)
   - Metadata correctness (stage, valid_until, terms, account link) (25 pts)
   - Line items correctness (qty, prices, names) (25 pts)
   - Grand total and timestamp anti-gaming (15 pts)
2. VLM Trajectory Verification (20 pts):
   - Verifies the agent actually utilized the SuiteCRM user interface.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are auditing an AI agent's performance on a CRM data entry task. 
The task was to create a new multi-line Quote for a customer named "Meridian Technologies" using the SuiteCRM interface.

Examine these screenshots from the agent's browser session.
1. Did the agent navigate to the "Quotes" module?
2. Did the agent open and interact with the Quote creation form?
3. Did the agent add line items using the interface (e.g., clicking "Add Row" or filling out product lines)?

Respond ONLY with a JSON object:
{
  "used_quotes_module": true/false,
  "interacted_with_form": true/false,
  "added_line_items_via_ui": true/false,
  "confidence": "high/medium/low",
  "reasoning": "Brief explanation"
}
"""

def verify_create_quote_line_items(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # -------------------------------------------------------------
    # 1. Read JSON result from container
    # -------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------
    # 2. Evaluate Database Record (80 points total)
    # -------------------------------------------------------------
    quote = result.get('quote', {})
    
    # Quote Existence (15 pts)
    if result.get('quote_found'):
        score += 15
        feedback_parts.append("Quote record found")
    else:
        feedback_parts.append("FAIL: Quote 'Q-2024-MER-001' not found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # Metadata (25 pts)
    if quote.get('stage', '').lower() == metadata.get('expected_stage', '').lower():
        score += 7
        feedback_parts.append("Stage correct")
        
    if metadata.get('expected_valid_until') in quote.get('valid_until', ''):
        score += 6
        feedback_parts.append("Valid Until date correct")
        
    # Net 30 is sometimes saved as "Net_30" or "Net 30" depending on dropdown keys
    payment_term = quote.get('payment_terms', '').lower().replace('_', ' ')
    if payment_term == metadata.get('expected_payment_terms', '').lower():
        score += 5
        feedback_parts.append("Payment terms correct")
        
    if metadata.get('expected_account', '').lower() in quote.get('account_name', '').lower():
        score += 7
        feedback_parts.append("Account correctly linked")
        
    # Line Items (25 pts)
    line_items = result.get('line_items', [])
    matched_items = 0
    
    for expected_li in metadata.get('line_items', []):
        exp_name = expected_li['name'].lower()
        exp_qty = expected_li['qty']
        exp_price = expected_li['price']
        
        found = False
        for actual_li in line_items:
            act_name = actual_li.get('name', '').lower()
            if exp_name in act_name or act_name in exp_name:
                try:
                    act_qty = float(actual_li.get('product_qty', 0))
                    act_price = float(actual_li.get('product_unit_price', 0))
                    
                    if abs(act_qty - exp_qty) < 0.1 and abs(act_price - exp_price) < 1.0:
                        found = True
                        break
                except ValueError:
                    pass
        
        if found:
            matched_items += 1
            score += 8
            
    if matched_items == 3:
        score += 1  # Bonus point for getting all 3 perfectly (total 25 pts)
        feedback_parts.append(f"All {matched_items} line items correct")
    else:
        feedback_parts.append(f"{matched_items}/3 line items perfectly matched")

    # Financial Total (5 pts)
    try:
        act_total = float(quote.get('total_amount', 0))
        exp_total = metadata.get('expected_total', 0)
        # Tolerance of 5% in case tax/discount settings differ slightly
        if abs(act_total - exp_total) / exp_total < 0.05:
            score += 5
            feedback_parts.append("Grand total accurate")
        else:
            feedback_parts.append(f"Grand total off (${act_total} vs ${exp_total})")
    except ValueError:
        pass

    # Anti-Gaming Timestamp (10 pts)
    task_start = result.get('task_start_time', 0)
    quote_epoch = result.get('quote_epoch', 0)
    
    if quote_epoch >= task_start:
        score += 10
        feedback_parts.append("Quote timestamp verified (created during task)")
    else:
        feedback_parts.append("FAIL: Quote timestamp predates task execution")

    # -------------------------------------------------------------
    # 3. VLM Trajectory Verification (20 points)
    # -------------------------------------------------------------
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('used_quotes_module'): vlm_score += 5
            if parsed.get('interacted_with_form'): vlm_score += 5
            if parsed.get('added_line_items_via_ui'): vlm_score += 10
            
            score += vlm_score
            feedback_parts.append(f"VLM UI usage verified ({vlm_score}/20 pts)")
    except Exception as e:
        logger.error(f"VLM Verification failed: {e}")
        feedback_parts.append("VLM Verification skipped/failed")

    # -------------------------------------------------------------
    # 4. Final Verdict
    # -------------------------------------------------------------
    # Pass requires a score of 60+, the quote record existing, and at least 2 correct line items
    passed = (score >= 60) and result.get('quote_found') and (matched_items >= 2)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }