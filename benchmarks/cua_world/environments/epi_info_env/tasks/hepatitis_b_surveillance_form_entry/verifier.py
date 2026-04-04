import json
import tempfile
import os
import logging

RESULT_PATH = "C:\\Users\\Docker\\hepatitis_b_surveillance_form_entry_result.json"

logger = logging.getLogger(__name__)


def verify_hepatitis_b_surveillance_form_entry(traj, env_info, task_info):
    """
    Scoring breakdown (100 pts total, pass >= 60):

    Three-module workflow: MakeView → Enter → Analysis

    - PRJ project file exists and is newly created: 20 pts
      (proves MakeView was used to create the project)
    - MDB database has CaseReport table with >= 6 records: 25 pts
      (proves Enter was used to add case data; partial credit >= 3 records = 12 pts)
    - HTML analysis output exists and is newly created: 15 pts
      (proves Analysis module was used with ROUTEOUT)
    - HTML contains HepB-relevant analysis content: 25 pts
      (FREQ/MEANS of the specific fields entered)
    - HTML file is substantial (>3KB): 15 pts
      (comprehensive analysis, not just an empty file)

    Pass threshold: 60/100
    """
    copy_from_env = env_info.get('copy_from_env')
    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result JSON: {e}"
        }
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []

    prj = result.get('prj_file', {})
    mdb = result.get('mdb_file', {})
    html = result.get('html_output', {})

    # Criterion 1: PRJ project file exists and is new (20 pts)
    # This proves the agent successfully used MakeView to create a project
    if prj.get('exists') and prj.get('is_new'):
        score += 20
        feedback_parts.append("HepBSurveillance.prj project file created (MakeView step complete).")
    elif prj.get('exists') and not prj.get('is_new'):
        feedback_parts.append("PRJ file exists but predates this task (pre-existing project).")
    else:
        feedback_parts.append("HepBSurveillance.prj project file not found — MakeView step not completed.")

    # Criterion 2: MDB has CaseReport table with records (25 pts)
    # Proves Enter module was used to input case data
    if mdb.get('exists') and mdb.get('is_new'):
        table_ok = mdb.get('table_exists', False)
        record_count = mdb.get('record_count', 0)

        if table_ok and record_count >= 6:
            score += 25
            feedback_parts.append(f"CaseReport table has {record_count} records (Enter step complete — need >= 6 for full credit).")
        elif table_ok and record_count >= 3:
            score += 12
            feedback_parts.append(f"CaseReport table has {record_count} records (partial credit — need >= 6 for full credit).")
        elif table_ok and record_count >= 1:
            score += 5
            feedback_parts.append(f"CaseReport table has {record_count} records (very few — need >= 6 for full credit).")
        elif mdb.get('exists') and not table_ok:
            feedback_parts.append("MDB exists but CaseReport table not found — form may have been created with a different name.")
        else:
            feedback_parts.append("MDB exists but is empty or CaseReport table missing.")
    elif mdb.get('exists') and not mdb.get('is_new'):
        feedback_parts.append("MDB file exists but predates this task.")
    else:
        feedback_parts.append("HepBSurveillance.mdb not found — Enter step not completed.")

    # Criterion 3: HTML analysis output exists and is new (15 pts)
    # Proves Analysis module was used with ROUTEOUT
    if html.get('exists') and html.get('is_new'):
        score += 15
        feedback_parts.append("hepb_analysis.html created (Analysis/ROUTEOUT step initiated).")
    elif html.get('exists') and not html.get('is_new'):
        feedback_parts.append("HTML file exists but predates this task (stale).")
    else:
        feedback_parts.append("hepb_analysis.html not found — Analysis/ROUTEOUT step not completed.")

    # Criterion 4: HTML contains HepB analysis content (25 pts)
    # Checks that agent ran FREQ/MEANS on the right fields
    if html.get('exists') and html.get('is_new'):
        has_freq = html.get('has_freq_kw', False)
        has_hepb = html.get('has_hepb_kw', False)
        has_field = html.get('has_field_kw', False)
        has_means = html.get('has_means_kw', False)

        if has_freq and (has_hepb or has_field) and has_means:
            score += 25
            feedback_parts.append("HTML contains comprehensive FREQ and MEANS analysis of HepB surveillance fields.")
        elif has_freq and (has_hepb or has_field):
            score += 15
            feedback_parts.append("HTML contains FREQ analysis of relevant fields but MEANS not detected.")
        elif has_freq:
            score += 8
            feedback_parts.append("HTML contains frequency output but HepB-specific field content not detected.")
        else:
            feedback_parts.append("HTML does not contain expected FREQ/MEANS analysis content.")

    # Criterion 5: HTML file is substantial (15 pts)
    if html.get('exists') and html.get('is_new'):
        size = html.get('size_bytes', 0)
        if size > 3000:
            score += 15
            feedback_parts.append(f"HTML file contains substantial analysis output ({size} bytes).")
        elif size > 500:
            score += 7
            feedback_parts.append(f"HTML file is small ({size} bytes) — analysis may be incomplete.")
        else:
            feedback_parts.append(f"HTML file is nearly empty ({size} bytes).")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
