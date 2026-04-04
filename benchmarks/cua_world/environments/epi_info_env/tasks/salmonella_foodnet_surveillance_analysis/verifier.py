import json
import tempfile
import os
import logging

RESULT_PATH = "C:\\Users\\Docker\\salmonella_foodnet_surveillance_analysis_result.json"

logger = logging.getLogger(__name__)


def verify_salmonella_foodnet_surveillance_analysis(traj, env_info, task_info):
    """
    Scoring breakdown (100 pts total, pass >= 60):
    - HTML output exists and is newly created: 15 pts
    - HTML contains frequency analysis with serotype/surveillance keywords: 20 pts
    - HTML contains MEANS/incidence rate analysis: 20 pts
    - HTML contains TABLES cross-tabulation analysis: 15 pts
    - HTML contains temporal filtering (SELECT/year filtering) evidence: 15 pts
    - CSV output exists and is newly created: 15 pts

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
        feedback_parts.append("HTML surveillance report created.")
    elif html.get('exists') and not html.get('is_new'):
        feedback_parts.append("HTML file exists but predates this task (stale).")
    else:
        feedback_parts.append("HTML surveillance report not found.")

    # Criterion 2: Frequency/descriptive with serotype and surveillance keywords (20 pts)
    if html.get('exists') and html.get('is_new'):
        has_freq = html.get('has_freq_kw', False)
        has_serotype = html.get('has_serotype_kw', False)
        has_site = html.get('has_site_kw', False)
        has_salmonella = html.get('has_salmonella_kw', False)

        if has_freq and has_serotype and has_site:
            score += 20
            feedback_parts.append("HTML contains frequency distributions of serotypes and surveillance sites.")
        elif has_freq and (has_serotype or has_site):
            score += 12
            feedback_parts.append("HTML contains frequency output with partial surveillance variable coverage.")
        elif has_freq:
            score += 5
            feedback_parts.append("HTML contains frequency output but limited surveillance-specific content.")
        else:
            feedback_parts.append("HTML does not contain frequency analysis.")

    # Criterion 3: MEANS/incidence rate analysis (20 pts)
    if html.get('exists') and html.get('is_new'):
        has_means = html.get('has_means_kw', False)
        has_serotype = html.get('has_serotype_kw', False)

        if has_means and has_serotype:
            score += 20
            feedback_parts.append("HTML contains incidence rate/MEANS analysis by serotype or site.")
        elif has_means:
            score += 10
            feedback_parts.append("HTML contains MEANS output but limited serotype context.")
        else:
            feedback_parts.append("HTML does not appear to contain MEANS/incidence rate analysis.")

    # Criterion 4: TABLES cross-tabulation (15 pts)
    if html.get('exists') and html.get('is_new'):
        if html.get('has_tables_kw', False):
            score += 15
            feedback_parts.append("HTML contains TABLES cross-tabulation output.")
        else:
            feedback_parts.append("HTML does not appear to contain TABLES cross-tabulation output.")

    # Criterion 5: Temporal/SELECT filtering evidence (15 pts)
    if html.get('exists') and html.get('is_new'):
        if html.get('has_select_kw', False) and html.get('has_serotype_kw', False):
            score += 15
            feedback_parts.append("HTML shows evidence of temporal filtering (SELECT/year-filtered analysis).")
        elif html.get('has_select_kw', False):
            score += 8
            feedback_parts.append("HTML contains some temporal filtering evidence.")
        else:
            feedback_parts.append("No evidence of SELECT/temporal filtering in HTML output.")

    # Criterion 6: CSV output exists and is new (15 pts)
    if csv.get('exists') and csv.get('is_new'):
        score += 15
        feedback_parts.append("CSV serotype summary file created.")
    elif csv.get('exists') and not csv.get('is_new'):
        feedback_parts.append("CSV file exists but predates this task.")
    else:
        feedback_parts.append("CSV serotype summary file not found.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
