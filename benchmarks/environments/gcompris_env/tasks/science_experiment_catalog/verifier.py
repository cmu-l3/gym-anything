#!/usr/bin/env python3
"""
Verifier for science_experiment_catalog task.

A science curriculum developer must navigate GCompris Science activities,
explore physics experiments (gravity, water cycle, canal lock), color/optics
activities (mixing paint, mixing light), and other science simulations (binary
bulbs, farm animals), then produce a detailed NGSS-aligned science curriculum
catalog report.

Scoring (100 points):
- Report file exists: 10
- Report created after task start (gate): 10
- Report is >=450 bytes: 10
- Physics/gravity/water content documented: 20
- Color/optics/mixing content documented: 20
- Other science activities documented: 15
- NGSS/curriculum alignment content: 15

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_science_experiment_catalog(traj, env_info, task_info):
    """Verify the science experiment catalog task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/science_experiment_catalog_result.json', tmp.name)
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
            "feedback": "Report file ~/Desktop/science_curriculum_report.txt was not created"
        }
    score += 10
    parts.append("Report file created (10/10)")

    # 2. GATE: Report created after task started (10 pts)
    if not result.get('report_modified_after_start'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file predates task start — no new work done (timestamp gate failed)"
        }
    score += 10
    parts.append("Report created after task start (10/10)")

    # 3. Report size (10 pts)
    size = result.get('report_size', 0)
    if size >= 450:
        score += 10
        parts.append(f"Report has substantial content ({size} bytes, 10/10)")
    elif size >= 180:
        score += 5
        parts.append(f"Report is brief ({size} bytes, 5/10)")
    else:
        parts.append(f"Report too short ({size} bytes, 0/10)")

    # 4. Physics/gravity/water content (20 pts)
    has_physics = result.get('has_physics_content', False)
    if has_physics:
        score += 20
        details = []
        if result.get('has_gravity_activity'):
            details.append("gravity")
        if result.get('has_watercycle_activity'):
            details.append("water cycle")
        if result.get('has_canal_activity'):
            details.append("canal lock")
        detail_str = "/".join(details) if details else "physics"
        parts.append(f"Physics experiments documented ({detail_str}, 20/20)")
    else:
        parts.append("No physics/gravity/water content found in report (0/20)")

    # 5. Color/optics/mixing content (20 pts)
    has_color = result.get('has_color_optics_content', False)
    if has_color:
        score += 20
        details = []
        if result.get('has_mixing_paint_activity'):
            details.append("mixing paint")
        if result.get('has_mixing_light_activity'):
            details.append("mixing light")
        detail_str = "/".join(details) if details else "color/optics"
        parts.append(f"Color/optics activities documented ({detail_str}, 20/20)")
    else:
        parts.append("No color/optics/mixing content found in report (0/20)")

    # 6. Other science activities (15 pts)
    has_other = result.get('has_other_science_content', False)
    if has_other:
        score += 15
        details = []
        if result.get('has_binary_activity'):
            details.append("binary bulbs")
        if result.get('has_farm_activity'):
            details.append("farm animals")
        detail_str = "/".join(details) if details else "other science"
        parts.append(f"Other science activities documented ({detail_str}, 15/15)")
    else:
        parts.append("No other science activities (binary/farm) found in report (0/15)")

    # 7. NGSS/curriculum alignment content (15 pts)
    has_curriculum = result.get('has_curriculum_alignment_content', False)
    if has_curriculum:
        score += 15
        parts.append("NGSS/curriculum alignment content present in report (15/15)")
    else:
        parts.append("No NGSS/curriculum alignment content found in report (0/15)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts)
    }
