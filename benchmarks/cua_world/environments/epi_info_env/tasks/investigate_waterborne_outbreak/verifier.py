import json
import tempfile
import os
import logging

RESULT_PATH = "C:\\Users\\Docker\\investigate_waterborne_outbreak_result.json"

logger = logging.getLogger(__name__)


def verify_investigate_waterborne_outbreak(traj, env_info, task_info):
    """
    Stub verifier for investigate_waterborne_outbreak.

    Full verification will be handled by vlm_checklist_verifier.
    This stub checks basic report existence and key findings.

    Scoring breakdown (100 pts total, pass >= 60):
    - Report file exists and is newly created: 10 pts
    - Report contains overall attack rate: 10 pts
    - Report identifies North as highest-rate neighborhood: 10 pts
    - Report identifies municipal/tap water as primary risk factor: 20 pts
    - Report includes risk ratio or odds ratio values: 10 pts
    - Report identifies swimming pool as confounder: 15 pts
    - Report addresses dose-response for water consumption: 10 pts
    - Report mentions filter as protective factor: 5 pts
    - Report includes adjusted odds ratio from logistic regression: 10 pts
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

    report = result.get('report', {})

    # Criterion 1: Report file exists and is new (10 pts)
    if report.get('exists') and report.get('is_new'):
        score += 10
        feedback_parts.append("Report file created during task.")
    elif report.get('exists') and not report.get('is_new'):
        feedback_parts.append("Report file exists but predates this task (stale).")
    else:
        feedback_parts.append("Report file not found at expected path.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Contains overall attack rate (10 pts)
    if report.get('has_attack_rate'):
        score += 10
        feedback_parts.append("Report contains attack rate percentage.")
    else:
        feedback_parts.append("No attack rate percentage found in report.")

    # Criterion 3: Identifies North as highest neighborhood (10 pts)
    if report.get('has_north'):
        score += 10
        feedback_parts.append("Report mentions North neighborhood.")
    else:
        feedback_parts.append("North neighborhood not mentioned in report.")

    # Criterion 4: Identifies municipal/tap water as primary risk factor (20 pts)
    if report.get('has_municipal'):
        score += 20
        feedback_parts.append("Report identifies municipal/tap water as risk factor.")
    else:
        feedback_parts.append("Municipal/tap water not identified in report.")

    # Criterion 5: Includes RR or OR values (10 pts)
    if report.get('has_risk_ratio') or report.get('has_odds_ratio'):
        score += 10
        feedback_parts.append("Report contains risk ratio or odds ratio values.")
    else:
        feedback_parts.append("No risk ratio or odds ratio values found in report.")

    # Criterion 6: Identifies swimming pool as confounder (15 pts)
    if report.get('has_swimming') and report.get('has_confounder'):
        score += 15
        feedback_parts.append("Report identifies swimming pool as confounder.")
    elif report.get('has_swimming'):
        score += 5
        feedback_parts.append("Report mentions swimming pool but doesn't clearly identify confounding.")
    else:
        feedback_parts.append("Swimming pool confounding not addressed in report.")

    # Criterion 7: Addresses dose-response (10 pts)
    if report.get('has_dose_response'):
        score += 10
        feedback_parts.append("Report addresses dose-response relationship.")
    else:
        feedback_parts.append("Dose-response relationship not addressed in report.")

    # Criterion 8: Mentions filter as protective (5 pts)
    if report.get('has_filter'):
        score += 5
        feedback_parts.append("Report mentions water filter as protective factor.")
    else:
        feedback_parts.append("Water filter protective effect not mentioned.")

    # Criterion 9: Includes adjusted OR from logistic regression (10 pts)
    if report.get('has_odds_ratio'):
        score += 10
        feedback_parts.append("Report includes odds ratio (likely from logistic regression).")
    else:
        feedback_parts.append("No adjusted odds ratio from logistic regression found.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
