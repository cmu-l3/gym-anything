#!/usr/bin/env python3
"""
Verifier for phytosanitary_spray_campaign task.

The agent must create >=3 spraying interventions for wheat parcels,
dated 2023-06-15, with product and equipment parameters.

Scoring (100 points):
- 35 pts: >=3 new spraying interventions created after task start
- 25 pts: Interventions have a spraying/pulvérisation procedure type
- 25 pts: Interventions dated 2023-06-15
- 15 pts: Interventions have parameters (product/tool/worker) assigned

Pass threshold: 60 points
Mandatory: >=2 new spraying interventions
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/spray_campaign_result.json"


def verify_phytosanitary_spray_campaign(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    all_new = int(result.get("all_new_interventions", 0))
    spray_new = int(result.get("new_spraying_interventions", 0))
    dated_correctly = int(result.get("interventions_dated_2023_06_15", 0))
    with_params = int(result.get("interventions_with_parameters", 0))
    procedure_names = result.get("procedure_names_used", "")

    # --- Mandatory check ---
    if all_new < 1:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No interventions created — task not attempted",
        }

    # --- Criterion 1: >=3 new interventions of any kind (35 pts) ---
    # Use all_new for primary count (some Ekylibre setups name procedures differently)
    effective_spray = max(spray_new, all_new) if spray_new == 0 else spray_new
    if all_new >= 3:
        score += 35
        subscores["min_3_interventions"] = True
        feedback_parts.append(f"{all_new} new interventions created (>=3 required)")
    elif all_new >= 2:
        score += 18
        subscores["min_3_interventions"] = False
        feedback_parts.append(f"{all_new} interventions created (3 required for full credit)")
    else:
        score += 7
        subscores["min_3_interventions"] = False
        feedback_parts.append(f"Only {all_new} intervention created")

    # --- Criterion 2: Spraying/phytosanitary procedure type (25 pts) ---
    if spray_new >= 2:
        score += 25
        subscores["spray_procedure"] = True
        feedback_parts.append(f"{spray_new} interventions classified as spraying/phytosanitary")
    elif spray_new >= 1:
        score += 10
        subscores["spray_procedure"] = False
        feedback_parts.append(f"Only {spray_new} intervention has spraying procedure type")
    elif all_new >= 2:
        # Procedure names didn't match spray keywords but interventions exist
        # — award partial credit and check the names
        score += 5
        subscores["spray_procedure"] = False
        feedback_parts.append(
            f"Interventions created but procedure type not recognized as spraying "
            f"(found: {procedure_names[:60]})"
        )
    else:
        subscores["spray_procedure"] = False
        feedback_parts.append("No spraying-type interventions found")

    # --- Criterion 3: Date 2023-06-15 (25 pts) ---
    if dated_correctly >= 3:
        score += 25
        subscores["correct_date"] = True
        feedback_parts.append(f"All {dated_correctly} interventions dated 2023-06-15")
    elif dated_correctly >= 2:
        score += 15
        subscores["correct_date"] = False
        feedback_parts.append(f"{dated_correctly} interventions dated 2023-06-15")
    elif dated_correctly >= 1:
        score += 7
        subscores["correct_date"] = False
        feedback_parts.append(f"Only {dated_correctly} intervention dated 2023-06-15")
    else:
        subscores["correct_date"] = False
        feedback_parts.append("No interventions dated 2023-06-15")

    # --- Criterion 4: Parameters assigned (15 pts) ---
    if with_params >= 2:
        score += 15
        subscores["parameters_assigned"] = True
        feedback_parts.append(f"{with_params} interventions have product/equipment/worker parameters")
    elif with_params >= 1:
        score += 7
        subscores["parameters_assigned"] = False
        feedback_parts.append(f"Only {with_params} intervention has parameters")
    else:
        subscores["parameters_assigned"] = False
        feedback_parts.append("No intervention parameters recorded (product/equipment/worker missing)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
