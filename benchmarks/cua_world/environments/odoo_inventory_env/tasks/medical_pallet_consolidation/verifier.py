#!/usr/bin/env python3
import json
import os
import tempfile


def verify_medical_pallet_consolidation(traj, env_info, task_info):
    """
    Verify medical pallet consolidation task.

    Scoring (100 pts total, pass threshold: 85):
      10 pts — Packages feature enabled in settings
      20 pts — Pallet Alpha correctly composed
      20 pts — Pallet Beta correctly composed
      20 pts — Pallet Gamma correctly composed
      15 pts — All packed stock is inside 'Rapid Deployment'
      15 pts — Anti-gaming: No loose stock in target location and exactly 3 packages exist.
               (If extra packages are created, score is capped at 55 to prevent gaming)
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/medical_pallet_result.json')
    expected_alpha = metadata.get('expected_alpha', {
        'Med-Syringe 10ml': 200, 'Med-Saline 500ml': 100, 'Med-Bandage Roll': 400
    })
    expected_beta = metadata.get('expected_beta', {
        'Med-Syringe 10ml': 300, 'Med-Saline 500ml': 100, 'Med-Bandage Roll': 600
    })
    expected_gamma = metadata.get('expected_gamma', {
        'Med-Gauze Pads 4x4': 800, 'Med-Surgical Gloves Size M': 600, 'Med-Surgical Gloves Size L': 600
    })

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(result_file, local_path)
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    score = 0
    feedback_parts = []
    
    if result.get('packages_enabled'):
        score += 10
        feedback_parts.append("PASS: Packages feature enabled (+10)")
    else:
        feedback_parts.append("FAIL: Packages feature NOT enabled")

    packages = {}
    loose_stock = []
    
    for q in result.get('quants', []):
        pkg_id = q.get('package_id')
        qty = q.get('quantity', 0)
        prod = q.get('product_name')
        
        if pkg_id is None:
            if qty > 0:
                loose_stock.append(q)
        else:
            if pkg_id not in packages:
                packages[pkg_id] = {}
            if prod not in packages[pkg_id]:
                packages[pkg_id][prod] = 0
            packages[pkg_id][prod] += qty

    def package_matches(pkg_contents, expected):
        pkg = {k: v for k, v in pkg_contents.items() if v > 0}
        if len(pkg) != len(expected): 
            return False
        for k, v in expected.items():
            if pkg.get(k, 0) != v: 
                return False
        return True

    alpha_found, beta_found, gamma_found = False, False, False

    for pkg_id, contents in packages.items():
        if not alpha_found and package_matches(contents, expected_alpha):
            alpha_found = True
        elif not beta_found and package_matches(contents, expected_beta):
            beta_found = True
        elif not gamma_found and package_matches(contents, expected_gamma):
            gamma_found = True

    if alpha_found:
        score += 20
        feedback_parts.append("PASS: Pallet Alpha successfully composed (+20)")
    else:
        feedback_parts.append("FAIL: Pallet Alpha composition incorrect/missing")
        
    if beta_found:
        score += 20
        feedback_parts.append("PASS: Pallet Beta successfully composed (+20)")
    else:
        feedback_parts.append("FAIL: Pallet Beta composition incorrect/missing")

    if gamma_found:
        score += 20
        feedback_parts.append("PASS: Pallet Gamma successfully composed (+20)")
    else:
        feedback_parts.append("FAIL: Pallet Gamma composition incorrect/missing")

    if alpha_found and beta_found and gamma_found:
        score += 15
        feedback_parts.append("PASS: All packages correctly located in Rapid Deployment (+15)")
    else:
        partial = 5 * sum([alpha_found, beta_found, gamma_found])
        if partial > 0:
            score += partial
            feedback_parts.append(f"PARTIAL: Location points (+{partial})")

    loose_qty = sum(q['quantity'] for q in loose_stock)
    num_packages = len(packages)

    if loose_qty == 0 and num_packages == 3 and (alpha_found or beta_found or gamma_found):
        score += 15
        feedback_parts.append("PASS: No loose stock and exact package count observed (+15)")
    else:
        if num_packages > 3:
            score = min(score, 55)
            feedback_parts.append(f"FAIL: Anti-gaming triggered — too many packages created ({num_packages}). Score capped at 55.")
        elif loose_qty > 0:
            feedback_parts.append(f"FAIL: Loose stock found in target location ({loose_qty} units).")
        elif num_packages < 3:
            feedback_parts.append(f"FAIL: Missing packages (only {num_packages} packages found in target location).")

    passed = score >= metadata.get('pass_threshold', 85)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }