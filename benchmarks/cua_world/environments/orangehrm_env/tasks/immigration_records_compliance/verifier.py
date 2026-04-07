#!/usr/bin/env python3
"""
Verifier for immigration_records_compliance task.

Context: Northgate Medical Center HR compliance audit requires passport
records for 3 international employees to be entered into OrangeHRM.

Scoring (100 pts total, pass threshold 80):

Per employee (35 pts each × 3 = 105, capped at 100):
  - Passport record exists in OrangeHRM:    20 pts
  - Passport number matches exactly:         15 pts

Note: Expiry date check removed — the year appears in the spec file and
is gameable without a correct passport number. Only the passport NUMBER
is evidence that the agent actually read and entered the right document.

Anti-Pattern 4 check (strategy enumeration):
  All 3 records exist but all wrong passport numbers: 3×20 = 60 < 80 ✓
  1 correct passport number: 1×35 + 2×20 = 75 < 80 → fail ✓
  2 correct passport numbers: 2×35 + 1×20 = 90 → pass ✓
  All 3 correct: 3×35 = 105 → capped 100 → pass ✓

Pass threshold: 80 (agent must enter at least 2 correct passport numbers)
Do-nothing score = 0 (no records exist after setup wipes them).
"""

import json
import os
import tempfile


def verify_immigration_records_compliance(traj, env_info, task_info):
    result_path = task_info.get("metadata", {}).get(
        "result_file", "/tmp/immigration_records_compliance_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_path, local_tmp)
        with open(local_tmp, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file '{result_path}': {e}",
        }
    finally:
        if os.path.exists(local_tmp):
            os.remove(local_tmp)

    score = 0
    feedback_parts = []

    def check_employee(name, has_key, num_key, expected_num):
        nonlocal score
        has = data.get(has_key, False)
        if has is True or has == "true":
            score += 20
            feedback_parts.append(f"PASS {name} passport record exists (+20)")
        else:
            feedback_parts.append(f"FAIL {name} passport record not found (+0)")
            return

        passport_no = (data.get(num_key) or "").strip().upper()
        if passport_no == expected_num.upper():
            score += 15
            feedback_parts.append(
                f"PASS {name} passport number '{passport_no}' matches (+15)"
            )
        else:
            feedback_parts.append(
                f"FAIL {name} passport number '{passport_no}' != expected '{expected_num}' (+0)"
            )

    check_employee("David Nguyen", "david_has_passport", "david_passport_no", "VNB456123")
    check_employee("Jessica Liu", "jessica_has_passport", "jessica_passport_no", "EA3456789")
    check_employee("Robert Patel", "robert_has_passport", "robert_passport_no", "K3812456")

    score = min(score, 100)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
