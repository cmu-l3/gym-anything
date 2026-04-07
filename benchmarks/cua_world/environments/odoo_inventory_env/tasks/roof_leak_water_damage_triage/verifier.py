import json
import os
import tempfile

def verify_roof_leak_triage(traj, env_info, task_info):
    """
    Verify Roof Leak Water Damage Triage task.

    Scoring (100 pts total, pass threshold: 85):
      15 pts — Aisle C (Bay 1 & Bay 2) is completely empty of stock.
      30 pts — Salvage items (10 pts each) successfully transferred to Aisle D/Bay 1.
      30 pts — Destroy/Ruined items (10 pts each) successfully scrapped/adjusted out.
      25 pts — Anti-gaming: Stock in other zones (Aisle A, Aisle B) remains untouched.
               (If control group is violated, total score is capped at 40 pts).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    pass_threshold = metadata.get('pass_threshold', 85)

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env("/tmp/roof_leak_result.json", local_path)
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load export data: {e}",
            "subscores": {}
        }
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    stock = result.get('stock', [])
    score = 0
    feedback = []

    # Helper: get qty for a code in a specific location (partial string match to handle Odoo hierarchies)
    def get_qty_in_loc(code, loc_substring):
        return sum(item['quantity'] for item in stock if item['code'] == code and loc_substring in item['location_name'])

    # Helper: get total internal quantity for a given product code
    def get_total_qty(code):
        return sum(item['quantity'] for item in stock if item['code'] == code)

    # 1. Aisle C Clearance Check (15 pts)
    aisle_c_qty = sum(item['quantity'] for item in stock if "Aisle C/Bay 1" in item['location_name'] or "Aisle C/Bay 2" in item['location_name'])
    if aisle_c_qty == 0:
        score += 15
        feedback.append("PASS: Aisle C (Bay 1 & 2) successfully cleared (+15)")
    else:
        feedback.append(f"FAIL: Aisle C still has {aisle_c_qty} units of stock")

    # 2. Salvage Check (30 pts)
    salvage_1 = get_qty_in_loc('BLD-WP-001', 'Aisle D/Bay 1')
    if salvage_1 == 60:
        score += 10
        feedback.append("PASS: Henry 208R Rubberized Wet Patch salvaged correctly (+10)")
    else:
        feedback.append(f"FAIL: Henry 208R in safe zone: {salvage_1} (Expected 60)")

    salvage_2 = get_qty_in_loc('BLD-WP-002', 'Aisle D/Bay 1')
    if salvage_2 == 150:
        score += 10
        feedback.append("PASS: SharkBite Brass Coupling salvaged correctly (+10)")
    else:
        feedback.append(f"FAIL: SharkBite Coupling in safe zone: {salvage_2} (Expected 150)")

    salvage_3 = get_qty_in_loc('BLD-WP-003', 'Aisle D/Bay 1')
    if salvage_3 == 30:
        score += 10
        feedback.append("PASS: Southwire Romex salvaged correctly (+10)")
    else:
        feedback.append(f"FAIL: Southwire Romex in safe zone: {salvage_3} (Expected 30)")

    # 3. Destroy/Scrap Check (30 pts)
    # BLD-VS-001 started with 140 (40 damaged, 100 control). Should be 100.
    vs_1_total = get_total_qty('BLD-VS-001')
    if vs_1_total == 100:
        score += 10
        feedback.append("PASS: USG Sheetrock Compound ruined stock scrapped (+10)")
    else:
        feedback.append(f"FAIL: USG Compound total internal qty is {vs_1_total} (Expected 100)")

    # BLD-VS-002 started with 15. All damaged. Should be 0.
    vs_2_total = get_total_qty('BLD-VS-002')
    if vs_2_total == 0:
        score += 10
        feedback.append("PASS: Kraft Paper Roll ruined stock scrapped (+10)")
    else:
        feedback.append(f"FAIL: Kraft Paper total internal qty is {vs_2_total} (Expected 0)")

    # BLD-VS-003 started with 25. All damaged. Should be 0.
    vs_3_total = get_total_qty('BLD-VS-003')
    if vs_3_total == 0:
        score += 10
        feedback.append("PASS: Owens Insulation ruined stock scrapped (+10)")
    else:
        feedback.append(f"FAIL: Owens Insulation total internal qty is {vs_3_total} (Expected 0)")

    # 4. Anti-Gaming Control Group (25 pts)
    control_1 = get_qty_in_loc('BLD-VS-001', 'Aisle B/Bay 1')
    control_2 = get_qty_in_loc('BLD-WP-002', 'Aisle A/Bay 3')

    if control_1 == 100 and control_2 == 50:
        score += 25
        feedback.append("PASS: Control group stock untouched (+25)")
    else:
        feedback.append(f"FAIL: Control group violated! (Control 1: {control_1}/100, Control 2: {control_2}/50). Score capped at 40.")
        score = min(score, 40)

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }