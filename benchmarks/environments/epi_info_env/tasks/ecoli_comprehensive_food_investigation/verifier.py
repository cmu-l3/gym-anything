import json
import tempfile
import os
import logging

RESULT_PATH = "C:\\Users\\Docker\\ecoli_comprehensive_food_investigation_result.json"

logger = logging.getLogger(__name__)


def verify_ecoli_comprehensive_food_investigation(traj, env_info, task_info):
    """
    Scoring breakdown (100 pts total, pass >= 60):
    - HTML output exists and is newly created: 15 pts
    - HTML contains frequency analysis with food variables and ILLDUM: 15 pts
    - HTML contains TABLES/attack rate tables for multiple food items (>=5): 25 pts
    - HTML contains logistic regression output: 25 pts
    - CSV output exists and is newly created: 10 pts
    - HTML file is large (>20KB indicating comprehensive analysis): 10 pts

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
        feedback_parts.append("HTML investigation output file created.")
    elif html.get('exists') and not html.get('is_new'):
        feedback_parts.append("HTML file exists but predates this task (stale).")
    else:
        feedback_parts.append("HTML analysis output not found.")

    # Criterion 2: FREQ analysis with food variables and ILLDUM (15 pts)
    if html.get('exists') and html.get('is_new'):
        food_count = html.get('food_var_count', 0)
        has_freq = html.get('has_freq_kw', False)
        has_illdum = html.get('has_illdum', False)

        if has_freq and food_count >= 5 and has_illdum:
            score += 15
            feedback_parts.append(f"HTML contains frequency analysis with {food_count} food variables and ILLDUM outcome.")
        elif has_freq and food_count >= 3:
            score += 8
            feedback_parts.append(f"HTML contains frequency analysis with {food_count} food variables (need >= 5 for full credit).")
        elif has_freq:
            score += 4
            feedback_parts.append("HTML contains frequency output but limited food variable coverage.")
        else:
            feedback_parts.append("HTML does not appear to contain frequency analysis of food variables.")

    # Criterion 3: TABLES/attack rate tables for multiple food items (25 pts)
    if html.get('exists') and html.get('is_new'):
        has_tables = html.get('has_tables_kw', False)
        has_multiple = html.get('multiple_food_tables', False)
        food_count = html.get('food_var_count', 0)

        if has_tables and has_multiple:
            score += 25
            feedback_parts.append(f"HTML contains attack rate tables for multiple food items ({food_count} food variables detected).")
        elif has_tables and food_count >= 3:
            score += 15
            feedback_parts.append(f"HTML contains TABLES output with {food_count} food variables (need >= 5 for full credit).")
        elif has_tables:
            score += 8
            feedback_parts.append("HTML contains TABLES output but limited food variable coverage.")
        else:
            feedback_parts.append("HTML does not contain attack rate table output.")

    # Criterion 4: Logistic regression (25 pts)
    if html.get('exists') and html.get('is_new'):
        has_logistic = html.get('has_logistic_kw', False)
        has_or = html.get('has_or_values', False)

        if has_logistic and has_or:
            score += 25
            feedback_parts.append("HTML contains logistic regression output with odds ratios.")
        elif has_logistic:
            score += 12
            feedback_parts.append("HTML contains logistic regression keyword but numeric OR values not detected.")
        else:
            feedback_parts.append("HTML does not appear to contain logistic regression output.")

    # Criterion 5: CSV output exists and is new (10 pts)
    if csv.get('exists') and csv.get('is_new'):
        score += 10
        feedback_parts.append("CSV risk factor summary file created.")
    elif csv.get('exists') and not csv.get('is_new'):
        feedback_parts.append("CSV file exists but predates this task.")
    else:
        feedback_parts.append("CSV risk factor file not found.")

    # Criterion 6: HTML file is large/comprehensive (10 pts)
    if html.get('exists') and html.get('is_new'):
        size = html.get('size_bytes', 0)
        if size > 20000:
            score += 10
            feedback_parts.append(f"HTML file is large and comprehensive ({size} bytes).")
        elif size > 5000:
            score += 5
            feedback_parts.append(f"HTML file is moderate size ({size} bytes); comprehensive analysis should be >20KB.")
        else:
            feedback_parts.append(f"HTML file is too small ({size} bytes) — analysis appears incomplete.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
