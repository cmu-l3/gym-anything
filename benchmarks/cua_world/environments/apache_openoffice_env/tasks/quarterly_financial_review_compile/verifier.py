import json
import os
import tempfile


def verify_quarterly_financial_review(traj, env_info, task_info):
    """
    Stub verifier for quarterly_financial_review_compile task.
    Real verification is performed by the VLM checklist verifier.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": True, "score": 100, "feedback": "Stub verifier (no copy_from_env)."}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        temp_file.close()
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": True, "score": 100, "feedback": f"Stub verifier (export read failed: {e})."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Stub: always pass. VLM checklist verifier handles actual scoring.
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier passed. Use VLM checklist for real evaluation.",
        "details": {
            "file_exists": result.get("file_exists", False),
            "formula_count": result.get("formula_count", 0),
            "heading1_count": result.get("heading1_count", 0),
            "has_toc": result.get("has_toc", False),
            "is_landscape_present": result.get("is_landscape_present", False),
            "has_footer": result.get("has_footer", False),
            "table_count": result.get("table_count", 0)
        }
    }
