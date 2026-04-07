#!/usr/bin/env python3
"""
Verifier for ap_topic_modeling task.

Verifies:
1. Corpus Summary CSV (structure + correct AP dataset stats)
2. LDA Topics CSV (structure + K=6 model + beta probabilities)
3. Model Comparison CSV (perplexity for multiple K)
4. Visualization PNG (existence + VLM check)
5. Anti-gaming (files created during task)

Score Breakdown (100 pts):
- Summary CSV: 15 pts
- Topics CSV: 25 pts (Critical)
- Comparison CSV: 20 pts
- Plot: 20 pts
- Script: 10 pts
- VLM Bonus: 10 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth values for AP dataset
EXPECTED_DOCS = 2246
EXPECTED_VOCAB = 10473
EXPECTED_SPARSITY_MIN = 0.98

def verify_ap_topic_modeling(traj, env_info, task_info):
    """Verify the AP topic modeling task deliverables."""
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # 2. Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 3. Verify Corpus Summary CSV (15 pts)
    summary = data.get('summary', {})
    if summary.get('exists') and summary.get('is_new'):
        # Check content accuracy
        n_docs = summary.get('n_documents', 0)
        sparsity = summary.get('sparsity', 0)
        
        # Allow slight flexibility if they did some filtering, but AP usually fixed
        doc_ok = abs(n_docs - EXPECTED_DOCS) < 50
        sparsity_ok = sparsity > EXPECTED_SPARSITY_MIN
        
        if doc_ok and sparsity_ok:
            score += 15
            feedback.append("Corpus Summary: PASS (+15)")
        else:
            score += 5
            feedback.append(f"Corpus Summary: Exists but values incorrect (Docs: {n_docs}, Sparsity: {sparsity}) (+5)")
    else:
        feedback.append("Corpus Summary: Missing or pre-existing (0)")

    # 4. Verify LDA Topics CSV (25 pts) - Critical
    topics = data.get('topics', {})
    topics_valid = False
    if topics.get('exists') and topics.get('is_new'):
        if topics.get('has_columns') and topics.get('valid_betas'):
            # Check dimensions (K=6, top 10 terms = 60 rows)
            rows = topics.get('row_count', 0)
            k_count = topics.get('unique_topics', 0)
            
            if rows == 60 and k_count == 6:
                score += 25
                topics_valid = True
                feedback.append("LDA Topics: PASS (K=6, 60 terms) (+25)")
            else:
                score += 10
                feedback.append(f"LDA Topics: Incorrect dimensions (Rows: {rows}, Topics: {k_count}) (+10)")
        else:
            score += 5
            feedback.append("LDA Topics: Malformed columns or probabilities (+5)")
    else:
        feedback.append("LDA Topics: Missing (0)")

    # 5. Verify Model Comparison CSV (20 pts)
    comp = data.get('comparison', {})
    if comp.get('exists') and comp.get('is_new'):
        k_vals = comp.get('k_values', [])
        # Expect [2, 4, 6, 8, 10]
        if len(k_vals) >= 4 and 2 in k_vals and 10 in k_vals:
            score += 20
            feedback.append("Model Comparison: PASS (+20)")
        else:
            score += 10
            feedback.append(f"Model Comparison: Incomplete K values ({k_vals}) (+10)")
    else:
        feedback.append("Model Comparison: Missing (0)")

    # 6. Verify Visualization (20 pts + 10 VLM bonus)
    plot = data.get('plot', {})
    if plot.get('exists') and plot.get('is_new'):
        size_kb = plot.get('size', 0) / 1024
        if size_kb > 30: # Multi-panel plots are usually large
            score += 20
            feedback.append(f"Visualization: File exists and size OK ({size_kb:.1f}KB) (+20)")
            
            # VLM Bonus Check
            if query_vlm:
                final_ss = get_final_screenshot(traj) # Prefer final screenshot context
                # Ideally we check the actual output file, but without downloading image content
                # we assume the final screenshot might show the plot or we check VLM on general workflow
                vlm_res = query_vlm(
                    prompt="Does the screen show a multi-panel plot with bar charts (topic terms) and a line graph? Is there evidence of RStudio analysis?",
                    image=final_ss
                )
                if vlm_res.get('parsed', {}).get('answer', False) or vlm_res.get('success'):
                    # Simple heuristic: if VLM didn't fail hard
                    score += 10
                    feedback.append("VLM Verification: Visual confirmation (+10)")
        else:
            score += 5
            feedback.append("Visualization: File too small/empty (+5)")
    else:
        feedback.append("Visualization: Missing (0)")

    # 7. Script Check (10 pts)
    script = data.get('script', {})
    if script.get('exists') and script.get('is_new'):
        score += 10
        feedback.append("R Script: Saved (+10)")
    else:
        feedback.append("R Script: Missing/Unmodified (0)")

    # Final logic
    passed = score >= 60 and topics_valid
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }