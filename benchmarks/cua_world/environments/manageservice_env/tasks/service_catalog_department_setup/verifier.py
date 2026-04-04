#!/usr/bin/env python3
"""
Verifier for service_catalog_department_setup task.

Scoring breakdown (100 pts total, pass threshold: 60):
  Criterion 1 (15 pts): 'Research Computing Services' department created.
  Criterion 2 (20 pts): 'Research Computing' top-level category created.
  Criterion 3 (30 pts): All 3 subcategories created: 'HPC Cluster Access', 'Research Data Storage',
                         'Scientific Software'. (10 pts each)
  Criterion 4 (20 pts): 'Research Computing Support Team' technician group created.
  Criterion 5 (15 pts): 'HPC Cluster Access Request' template created.

Wrong-target gate: If the category 'Research Computing' was NOT created, return score=0
(no subcategories, templates, or routing can exist without the parent category).
Partial credit allowed for individual criteria.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_service_catalog_department_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')

    if copy_from_env is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verifier error: copy_from_env not available."
        }

    with tempfile.TemporaryDirectory() as tmp_dir:
        result_path = os.path.join(tmp_dir, 'result.json')
        try:
            copy_from_env('/tmp/service_catalog_department_setup_result.json', result_path)
            with open(result_path) as f:
                data = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not read result file from VM: {e}"
            }

    score = 0
    feedback_parts = []
    subscores = {}

    category_created = data.get('category_created', False)
    dept_created = data.get('dept_created', False)

    # --- Wrong-target gate: core category must exist ---
    if not category_created and not dept_created:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: Neither 'Research Computing' category nor 'Research Computing Services' department "
                "was found in the system. The core deliverables of this task were not completed. "
                "The agent must create the department and service category structure."
            ),
            "subscores": {
                "department": 0,
                "category": 0,
                "subcategories": 0,
                "group": 0,
                "template": 0
            }
        }

    # --- Criterion 1: Department created ---
    if dept_created:
        score += 15
        subscores['department'] = 15
        feedback_parts.append("PASS: 'Research Computing Services' department created. (+15 pts)")
    else:
        subscores['department'] = 0
        feedback_parts.append("FAIL: 'Research Computing Services' department not found. (+0 pts)")

    # --- Criterion 2: Category created ---
    if category_created:
        score += 20
        subscores['category'] = 20
        feedback_parts.append("PASS: 'Research Computing' service category created. (+20 pts)")
    else:
        subscores['category'] = 0
        feedback_parts.append("FAIL: 'Research Computing' service category not found. (+0 pts)")

    # --- Criterion 3: Subcategories (10 pts each) ---
    subcat_score = 0
    subcat_feedback = []

    hpc_created = data.get('subcat_hpc_created', False)
    storage_created = data.get('subcat_storage_created', False)
    software_created = data.get('subcat_software_created', False)

    if hpc_created:
        subcat_score += 10
        subcat_feedback.append("'HPC Cluster Access' ✓")
    else:
        subcat_feedback.append("'HPC Cluster Access' ✗")

    if storage_created:
        subcat_score += 10
        subcat_feedback.append("'Research Data Storage' ✓")
    else:
        subcat_feedback.append("'Research Data Storage' ✗")

    if software_created:
        subcat_score += 10
        subcat_feedback.append("'Scientific Software' ✓")
    else:
        subcat_feedback.append("'Scientific Software' ✗")

    score += subcat_score
    subscores['subcategories'] = subcat_score

    subcat_count = data.get('subcategories_created_count', 0)
    if subcat_score == 30:
        feedback_parts.append(
            f"PASS: All 3 subcategories created ({', '.join(subcat_feedback)}). (+{subcat_score} pts)"
        )
    elif subcat_score > 0:
        feedback_parts.append(
            f"PARTIAL: {subcat_count}/3 subcategories created ({', '.join(subcat_feedback)}). (+{subcat_score} pts)"
        )
    else:
        feedback_parts.append(
            f"FAIL: No required subcategories found ({', '.join(subcat_feedback)}). (+0 pts)"
        )

    # --- Criterion 4: Technician group created ---
    group_created = data.get('group_created', False)
    if group_created:
        score += 20
        subscores['group'] = 20
        feedback_parts.append("PASS: 'Research Computing Support Team' group created. (+20 pts)")
    else:
        subscores['group'] = 0
        feedback_parts.append(
            "FAIL: 'Research Computing Support Team' technician group not found. (+0 pts)"
        )

    # --- Criterion 5: Request template created ---
    template_created = data.get('template_created', False)
    if template_created:
        score += 15
        subscores['template'] = 15
        feedback_parts.append("PASS: 'HPC Cluster Access Request' template created. (+15 pts)")
    else:
        subscores['template'] = 0
        feedback_parts.append(
            "FAIL: 'HPC Cluster Access Request' template not found. (+0 pts)"
        )

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
