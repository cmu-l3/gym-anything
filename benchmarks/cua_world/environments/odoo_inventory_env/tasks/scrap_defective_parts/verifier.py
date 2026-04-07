#!/usr/bin/env python3
import json
import os
import tempfile
from datetime import datetime

def verify_scrap_defective_parts(traj, env_info, task_info):
    """
    Verify scrap orders for defective parts.

    Scoring (100 pts total, pass threshold: 55):
    - 5 Target Products (17 pts each):
        - 7 pts: Scrap order created for the product
        - 5 pts: Scrap order quantity is exactly correct
        - 5 pts: Scrap order state is 'done' (validated)
    - 1 Distractor Product (15 pts):
        - 15 pts: NOT scrapped at all (no scrap orders)
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/scrap_task_result.json')
    targets = metadata.get('targets', {
        'SCRAP-001': 15,
        'SCRAP-002': 8,
        'SCRAP-003': 3,
        'SCRAP-005': 25,
        'SCRAP-006': 6
    })
    distractor = metadata.get('distractor', 'SCRAP-004')
    
    score = 0
    subscores = {}
    feedback_parts = []

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export file not found: {e}",
            "subscores": {},
        }

    try:
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse export result: {e}",
            "subscores": {},
        }
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    products = result.get('products', {})

    found_count = sum(1 for p in products.values() if p.get('found', False))
    if found_count < 6:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Only {found_count}/6 products found — environment setup may have failed",
            "subscores": {},
        }

    # Verify Target Products
    for code, expected_qty in targets.items():
        prod_data = products.get(code, {})
        scraps = prod_data.get('scraps', [])
        
        has_scrap = len(scraps) > 0
        qty_correct = False
        is_done = False
        
        # Check all scrap orders for this product to find best match
        best_pts = 0
        best_feedback = f"FAIL: No scrap order for {code}"
        
        if has_scrap:
            for s in scraps:
                current_pts = 7
                state_ok = (s.get('state') == 'done')
                qty_ok = (abs(s.get('qty', 0) - expected_qty) < 0.01)
                
                if qty_ok: current_pts += 5
                if state_ok: current_pts += 5
                
                fb = f"Scrap for {code}: "
                if qty_ok and state_ok:
                    fb += f"Perfect (+17)"
                else:
                    fb += f"Found (+7), "
                    fb += f"Qty {s.get('qty')} vs {expected_qty} " + ("(+5)" if qty_ok else "(+0)") + ", "
                    fb += f"State {s.get('state')} " + ("(+5)" if state_ok else "(+0)")
                
                if current_pts > best_pts:
                    best_pts = current_pts
                    best_feedback = fb
                    
                    qty_correct = qty_ok
                    is_done = state_ok
        
        score += best_pts
        subscores[f'{code}_scrapped'] = has_scrap
        subscores[f'{code}_qty_correct'] = qty_correct
        subscores[f'{code}_done'] = is_done
        feedback_parts.append(best_feedback)

    # Verify Distractor Product
    distractor_data = products.get(distractor, {})
    distractor_scraps = distractor_data.get('scraps', [])
    
    if len(distractor_scraps) == 0:
        score += 15
        subscores[f'{distractor}_untouched'] = True
        feedback_parts.append(f"PASS: Distractor {distractor} correctly untouched (+15)")
    else:
        subscores[f'{distractor}_untouched'] = False
        feedback_parts.append(f"FAIL: Distractor {distractor} was incorrectly scrapped (+0)")

    passed = (score >= 55)

    return {
        "passed": passed,
        "score": min(100, max(0, int(score))),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }