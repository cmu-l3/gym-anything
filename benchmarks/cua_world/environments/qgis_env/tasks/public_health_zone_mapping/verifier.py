import json
import os
import tempfile


# Ground truth: exactly these 7 tracts should be in the output
QUALIFYING_TRACTS = {"CT-003", "CT-007", "CT-011", "CT-014", "CT-016", "CT-018", "CT-020"}
NON_QUALIFYING_TRACTS = {
    "CT-001", "CT-002", "CT-004", "CT-005", "CT-006",
    "CT-008", "CT-009", "CT-010", "CT-012", "CT-013",
    "CT-015", "CT-017", "CT-019"
}


def verify_public_health_zone_mapping(traj, env_info, task_info):
    """
    Verify public health zone mapping — High-Risk Health Zone designation.

    Scoring (100 pts total, pass threshold: 65):
      10 pts — Output file exists and is valid GeoJSON FeatureCollection
      40 pts — Qualifying tracts present (proportional: correct_present/7 * 40)
      30 pts — Non-qualifying tracts absent (proportional: correct_absent/13 * 30)
      20 pts — Exact match (exactly 7 correct features, no extras)

    Strategy enumeration:
      Do-nothing:                   0 pts  → FAIL
      Export all 20:               10+40+0+0   = 50 pts < 65 → FAIL
      Export 7 correct only:       10+40+30+20 = 100 pts     → PASS
      Export 5 correct, 0 wrong:   10+29+30+0  = 69 pts > 65 → PASS
      Export 4 correct, 0 wrong:   10+23+30+0  = 63 pts < 65 → FAIL
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/public_health_zone_result.json')
    pass_threshold = metadata.get('pass_threshold', 65)
    qualifying = set(metadata.get('qualifying_tracts', list(QUALIFYING_TRACTS)))
    non_qualifying = set(metadata.get('non_qualifying_tracts', list(NON_QUALIFYING_TRACTS)))

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
    except Exception as e:
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

    output_exists = result.get('output_file_exists', False)
    valid_geojson = result.get('valid_geojson', False)
    feature_count = result.get('feature_count', 0)
    tract_ids_raw = result.get('tract_ids_found', [])
    tract_ids_found = set(str(t).strip() for t in tract_ids_raw if t)

    # --- Criterion 1: File exists + valid GeoJSON ---
    if output_exists and valid_geojson:
        score += 10
        subscores['file_valid'] = True
        feedback_parts.append(f"PASS: Output GeoJSON exists and is valid ({feature_count} features) (+10)")
    elif output_exists:
        score += 5
        subscores['file_valid'] = False
        feedback_parts.append("PARTIAL: Output file exists but is not valid GeoJSON (+5)")
    else:
        subscores['file_valid'] = False
        feedback_parts.append("FAIL: No output GeoJSON file found at expected path")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    # --- Criterion 2: Qualifying tracts present ---
    correct_present = tract_ids_found & qualifying
    correct_present_count = len(correct_present)
    present_score = int((correct_present_count / len(qualifying)) * 40)
    score += present_score

    if correct_present_count == len(qualifying):
        subscores['qualifying_present'] = True
        feedback_parts.append(f"PASS: All {len(qualifying)} qualifying tracts present (+{present_score})")
    else:
        subscores['qualifying_present'] = False
        missing = qualifying - correct_present
        feedback_parts.append(
            f"PARTIAL: {correct_present_count}/{len(qualifying)} qualifying tracts present (+{present_score}) | "
            f"Missing: {', '.join(sorted(missing))}"
        )

    # --- Criterion 3: Non-qualifying tracts absent ---
    wrong_present = tract_ids_found & non_qualifying
    correct_absent_count = len(non_qualifying) - len(wrong_present)
    absent_score = int((correct_absent_count / len(non_qualifying)) * 30)
    score += absent_score

    if not wrong_present:
        subscores['non_qualifying_absent'] = True
        feedback_parts.append(f"PASS: All {len(non_qualifying)} non-qualifying tracts correctly excluded (+{absent_score})")
    else:
        subscores['non_qualifying_absent'] = False
        feedback_parts.append(
            f"PARTIAL: {len(wrong_present)} non-qualifying tracts incorrectly included: "
            f"{', '.join(sorted(wrong_present))} (+{absent_score})"
        )

    # --- Criterion 4: Exact match bonus ---
    exact_match = (tract_ids_found == qualifying)
    if exact_match:
        score += 20
        subscores['exact_match'] = True
        feedback_parts.append("PASS: Exact match — precisely the 7 qualifying tracts, no extras (+20)")
    else:
        subscores['exact_match'] = False
        if tract_ids_found != qualifying:
            extra = tract_ids_found - qualifying - non_qualifying
            if extra:
                feedback_parts.append(f"FAIL: Exact match failed — unexpected tract IDs: {', '.join(sorted(extra))}")
            else:
                feedback_parts.append("FAIL: Exact match failed — incorrect set of tracts selected")

    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "pass_threshold": pass_threshold,
            "feature_count": feature_count,
            "qualifying_found": sorted(correct_present),
            "qualifying_missing": sorted(qualifying - correct_present),
            "wrong_inclusions": sorted(wrong_present),
        },
    }
