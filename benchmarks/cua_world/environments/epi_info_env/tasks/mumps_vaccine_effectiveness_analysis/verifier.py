import json
import tempfile
import os
import logging
import re

RESULT_PATH = "C:\\Users\\Docker\\mumps_vaccine_effectiveness_analysis_result.json"

logger = logging.getLogger(__name__)


def verify_mumps_vaccine_effectiveness_analysis(traj, env_info, task_info):
    """
    Scoring breakdown (100 pts total, pass >= 60):
    - HTML output exists and is newly created (mtime > task_start): 15 pts
    - HTML contains frequency analysis (FREQ keyword + data): 20 pts
    - HTML contains 2x2 table / odds ratio analysis: 20 pts
    - HTML contains logistic regression output: 25 pts
    - CSV output exists and is newly created: 10 pts
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
    task_start = result.get('task_start', 0)

    # Criterion 1: HTML output exists and is new (15 pts)
    if html.get('exists') and html.get('is_new'):
        score += 15
        feedback_parts.append("HTML analysis output file created.")
    elif html.get('exists') and not html.get('is_new'):
        feedback_parts.append("HTML file exists but was not created during this task (stale file).")
    else:
        feedback_parts.append("HTML analysis output file not found.")

    # Criterion 2: HTML contains frequency analysis (20 pts)
    if html.get('exists') and html.get('is_new'):
        if html.get('has_freq_keyword') and html.get('has_illness_kw'):
            score += 20
            feedback_parts.append("HTML contains frequency analysis output.")
        elif html.get('has_freq_keyword'):
            score += 10
            feedback_parts.append("HTML contains FREQ keyword but missing illness/case terminology.")
        else:
            feedback_parts.append("HTML does not appear to contain frequency analysis.")

    # Criterion 3: HTML contains 2x2 table / odds ratio (20 pts)
    if html.get('exists') and html.get('is_new'):
        if html.get('has_tables_kw') and html.get('has_vaccination_kw'):
            score += 20
            feedback_parts.append("HTML contains 2x2 table/odds ratio analysis with vaccination variable.")
        elif html.get('has_tables_kw'):
            score += 10
            feedback_parts.append("HTML contains TABLES/odds ratio output but vaccination variable not clearly identified.")
        else:
            feedback_parts.append("HTML does not contain 2x2 table or odds ratio output.")

    # Criterion 4: HTML contains logistic regression (25 pts)
    if html.get('exists') and html.get('is_new'):
        if html.get('has_logistic_kw') and html.get('has_or_values'):
            score += 25
            feedback_parts.append("HTML contains logistic regression output with odds ratios.")
        elif html.get('has_logistic_kw'):
            score += 12
            feedback_parts.append("HTML contains logistic regression keyword but no numeric OR values detected.")
        else:
            feedback_parts.append("HTML does not appear to contain logistic regression output.")

    # Criterion 5: CSV output exists and is new (10 pts)
    if csv.get('exists') and csv.get('is_new'):
        score += 10
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
            feedback_parts.append(f"HTML file is too small ({size} bytes) — may have incomplete output.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
