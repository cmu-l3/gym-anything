import json
import tempfile
import os
import logging

RESULT_PATH = "C:\\Users\\Docker\\hiv_transmission_route_analysis_result.json"

logger = logging.getLogger(__name__)


def verify_hiv_transmission_route_analysis(traj, env_info, task_info):
    """
    Scoring breakdown (100 pts total, pass >= 60):
    - HTML output exists and is newly created: 15 pts
    - HTML contains frequency/descriptive analysis with HIV/transmission keywords: 20 pts
    - HTML contains TABLES or cross-tabulation analysis: 20 pts
    - HTML contains stratified/SELECT analysis evidence: 20 pts
    - CSV output exists and is newly created: 15 pts
    - HTML file is substantial (>5KB): 10 pts

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

    html = result.get('html_output', {})
    csv = result.get('csv_output', {})

    # Criterion 1: HTML output exists and is new (15 pts)
    if html.get('exists') and html.get('is_new'):
        score += 15
        feedback_parts.append("HTML analysis output file created.")
    elif html.get('exists') and not html.get('is_new'):
        feedback_parts.append("HTML file exists but was not created during this task (pre-existing file).")
    else:
        feedback_parts.append("HTML analysis output not found.")

    # Criterion 2: Frequency/descriptive analysis with HIV-relevant content (20 pts)
    if html.get('exists') and html.get('is_new'):
        has_freq = html.get('has_freq_kw', False)
        has_hiv = html.get('has_hiv_kw', False)
        has_demo = html.get('has_demo_kw', False)
        has_trans = html.get('has_transmission_kw', False)

        if has_freq and (has_hiv or has_trans) and has_demo:
            score += 20
            feedback_parts.append("HTML contains comprehensive frequency/descriptive analysis with relevant HIV epidemiology variables.")
        elif has_freq and (has_hiv or has_trans):
            score += 12
            feedback_parts.append("HTML contains frequency analysis with HIV content but missing demographic breakdown.")
        elif has_freq:
            score += 5
            feedback_parts.append("HTML contains frequency output but limited HIV-relevant content.")
        else:
            feedback_parts.append("HTML does not appear to contain frequency analysis.")

    # Criterion 3: TABLES / cross-tabulation (20 pts)
    if html.get('exists') and html.get('is_new'):
        if html.get('has_tables_kw', False) and html.get('has_transmission_kw', False):
            score += 20
            feedback_parts.append("HTML contains cross-tabulation analysis of transmission categories.")
        elif html.get('has_tables_kw', False):
            score += 10
            feedback_parts.append("HTML contains TABLES output but transmission categories not clearly identified.")
        else:
            feedback_parts.append("HTML does not contain cross-tabulation output.")

    # Criterion 4: Stratified/SELECT analysis (20 pts)
    if html.get('exists') and html.get('is_new'):
        has_select = html.get('has_select_evidence', False)
        has_demo = html.get('has_demo_kw', False)
        if has_select and has_demo:
            score += 20
            feedback_parts.append("HTML contains evidence of stratified analysis (SELECT-filtered subgroup analysis).")
        elif has_select:
            score += 10
            feedback_parts.append("HTML contains some stratified analysis evidence.")
        else:
            feedback_parts.append("No evidence of stratified/SELECT analysis in HTML output.")

    # Criterion 5: CSV output exists and is new (15 pts)
    if csv.get('exists') and csv.get('is_new'):
        score += 15
        feedback_parts.append("CSV summary file created.")
    elif csv.get('exists') and not csv.get('is_new'):
        feedback_parts.append("CSV file exists but was not created during this task.")
    else:
        feedback_parts.append("CSV summary file not found.")

    # Criterion 6: HTML file is substantial (10 pts)
    if html.get('exists') and html.get('is_new'):
        size = html.get('size_bytes', 0)
        if size > 5000:
            score += 10
            feedback_parts.append(f"HTML file is substantial ({size} bytes).")
        else:
            feedback_parts.append(f"HTML file is too small ({size} bytes).")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
