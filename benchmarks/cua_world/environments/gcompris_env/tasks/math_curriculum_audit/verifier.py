#!/usr/bin/env python3
"""
Verifier for math_curriculum_audit task.

A curriculum coordinator must navigate all three Math sub-tabs in GCompris
(Numeration, Arithmetic, Measures), interact with activities, and write a
formal curriculum audit report.

Scoring (100 points):
- Report file exists: 10
- Report created after task start (gate): 15
- Report is ≥400 bytes: 10
- Numeration section present: 20
- Arithmetic section present: 20
- Measures section present: 10
- 3+ math activity name keywords: 15

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_math_curriculum_audit(traj, env_info, task_info):
    """Verify the mathematics curriculum audit task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/math_curriculum_audit_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # 1. Report exists (10 pts)
    if not result.get('report_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file ~/Desktop/math_curriculum_audit.txt was not created"
        }
    score += 10
    parts.append("Report file created (10/10)")

    # 2. GATE: Report must be created after task started (15 pts)
    if not result.get('report_modified_after_start'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file predates task start — no new work done (timestamp gate failed)"
        }
    score += 15
    parts.append("Report created after task start (15/15)")

    # 3. Report has substantial content (10 pts)
    size = result.get('report_size', 0)
    if size >= 400:
        score += 10
        parts.append(f"Report has substantial content ({size} bytes, 10/10)")
    elif size >= 150:
        score += 5
        parts.append(f"Report exists but is thin ({size} bytes, 5/10)")
    else:
        parts.append(f"Report too short ({size} bytes, 0/10)")

    # 4. Numeration section (20 pts)
    if result.get('has_numeration_section'):
        score += 20
        parts.append("Numeration section documented (20/20)")
    else:
        parts.append("Missing Numeration section (0/20)")

    # 5. Arithmetic section (20 pts)
    if result.get('has_arithmetic_section'):
        score += 20
        parts.append("Arithmetic section documented (20/20)")
    else:
        parts.append("Missing Arithmetic section (0/20)")

    # 6. Measures section (10 pts)
    if result.get('has_measures_section'):
        score += 10
        parts.append("Measures section documented (10/10)")
    else:
        parts.append("Missing Measures section (0/10)")

    # 7. Specific activity name keywords (15 pts)
    # Count how many distinct math activity keywords appear
    activity_keywords = [
        ('has_additions_keyword', 'additions'),
        ('has_subtraction_keyword', 'subtraction'),
        ('has_count_keyword', 'counting'),
        ('has_numbers_keyword', 'numbers'),
        ('has_algebra_keyword', 'algebra'),
        ('has_weight_keyword', 'weight/ruler'),
    ]
    kw_count = sum(1 for k, _ in activity_keywords if result.get(k))

    if kw_count >= 3:
        score += 15
        parts.append(f"Activity names well-documented ({kw_count}/6 keywords, 15/15)")
    elif kw_count == 2:
        score += 8
        parts.append(f"Some activity names mentioned ({kw_count}/6 keywords, 8/15)")
    elif kw_count == 1:
        score += 3
        parts.append(f"Minimal activity documentation ({kw_count}/6 keywords, 3/15)")
    else:
        parts.append("No specific activity names found in report (0/15)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts)
    }
