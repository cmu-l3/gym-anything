import json
import os
import tempfile
import math


# Ground truth: precomputed PMT values and risk categories for 20 loans
# PMT formula: principal * (monthly_rate * (1+monthly_rate)^n) / ((1+monthly_rate)^n - 1)
LOAN_DATA = [
    # (loan_id, principal, annual_rate, term, credit_score, dti, ltv)
    ("L001", 185000, 0.0675, 360, 720, 0.28, 0.78),
    ("L002", 320000, 0.0750, 360, 680, 0.38, 0.85),
    ("L003",  95000, 0.0595, 180, 760, 0.22, 0.65),
    ("L004", 450000, 0.0825, 360, 630, 0.42, 0.92),
    ("L005", 125000, 0.0625, 240, 745, 0.30, 0.70),
    ("L006", 275000, 0.0700, 360, 695, 0.35, 0.82),
    ("L007",  55000, 0.0550, 120, 800, 0.18, 0.55),
    ("L008", 390000, 0.0800, 360, 645, 0.44, 0.88),
    ("L009", 165000, 0.0650, 300, 730, 0.32, 0.72),
    ("L010", 220000, 0.0725, 360, 705, 0.36, 0.80),
    ("L011", 480000, 0.0850, 360, 615, 0.46, 0.95),
    ("L012",  78000, 0.0575, 180, 785, 0.24, 0.60),
    ("L013", 310000, 0.0775, 360, 660, 0.40, 0.86),
    ("L014", 145000, 0.0625, 240, 755, 0.27, 0.68),
    ("L015", 265000, 0.0700, 360, 690, 0.37, 0.81),
    ("L016",  88000, 0.0560, 120, 810, 0.20, 0.52),
    ("L017", 425000, 0.0825, 360, 625, 0.45, 0.91),
    ("L018", 195000, 0.0660, 360, 725, 0.31, 0.75),
    ("L019", 340000, 0.0775, 360, 665, 0.41, 0.87),
    ("L020", 115000, 0.0590, 180, 770, 0.26, 0.62),
]

RISK_CATEGORIES = {
    "Low Risk": 0.005,
    "Moderate Risk": 0.020,
    "High Risk": 0.050,
    "Critical Risk": 0.100,
}


def compute_pmt(principal, annual_rate, term_months):
    r = annual_rate / 12
    if r == 0:
        return principal / term_months
    return principal * (r * (1 + r) ** term_months) / ((1 + r) ** term_months - 1)


def compute_credit_component(score):
    if score >= 750: return 1.0
    if score >= 700: return 1.5
    if score >= 650: return 2.5
    if score >= 600: return 3.5
    return 5.0


def compute_dti_component(dti):
    if dti < 0.30: return 1.0
    if dti <= 0.35: return 2.0
    if dti <= 0.40: return 3.0
    return 4.5


def compute_ltv_component(ltv):
    if ltv < 0.70: return 1.0
    if ltv <= 0.80: return 1.5
    if ltv <= 0.90: return 2.5
    return 4.0


def compute_risk_score(score, dti, ltv):
    return compute_credit_component(score) + compute_dti_component(dti) + compute_ltv_component(ltv)


def compute_risk_category(risk_score):
    if risk_score <= 4.5: return "Low Risk"
    if risk_score <= 7.0: return "Moderate Risk"
    if risk_score <= 9.5: return "High Risk"
    return "Critical Risk"


# Precompute ground truth
GROUND_TRUTH = []
for loan in LOAN_DATA:
    lid, principal, rate, term, score, dti, ltv = loan
    pmt = compute_pmt(principal, rate, term)
    rs = compute_risk_score(score, dti, ltv)
    cat = compute_risk_category(rs)
    default_rate = RISK_CATEGORIES[cat]
    el = principal * default_rate
    GROUND_TRUTH.append({
        'loan_id': lid,
        'pmt': pmt,
        'risk_score': rs,
        'category': cat,
        'expected_loss': el,
    })


def parse_spreadsheet(parsed_data):
    """Extract loan data from the parsed spreadsheet."""
    sheets = parsed_data.get('sheets', {})

    # Try to find the Loan Portfolio sheet
    portfolio_sheet = None
    for name in ['Loan Portfolio', 'Sheet1', 'loan_portfolio', 'Portfolio']:
        if name in sheets:
            portfolio_sheet = sheets[name]
            break
    if not portfolio_sheet:
        for name, data in sheets.items():
            if data and len(data) > 5:
                portfolio_sheet = data
                break

    if not portfolio_sheet:
        return []

    # Find header row (look for "LoanAmount" or "MonthlyPayment")
    header_row_idx = None
    for i, row in enumerate(portfolio_sheet):
        if row and any(
            str(cell).strip() in ('LoanID', 'LoanAmount', 'MonthlyPayment')
            for cell in row if cell is not None
        ):
            header_row_idx = i
            break

    if header_row_idx is None:
        return []

    headers = [str(h).strip() if h is not None else '' for h in portfolio_sheet[header_row_idx]]

    # Map column indices
    col_map = {}
    for i, h in enumerate(headers):
        for key in ['LoanID', 'LoanAmount', 'AnnualRate', 'TermMonths', 'CreditScore',
                    'DTI_Ratio', 'LTV_Ratio', 'MonthlyPayment', 'RiskScore', 'RiskCategory', 'ExpectedLoss']:
            if h == key or h.lower().replace(' ', '_') == key.lower():
                col_map[key] = i

    rows = []
    for row in portfolio_sheet[header_row_idx + 1:]:
        if not row or all(cell is None for cell in row):
            continue
        row_data = {}
        for key, idx in col_map.items():
            if idx < len(row):
                row_data[key] = row[idx]
        if row_data.get('LoanID') and str(row_data['LoanID']).startswith('L'):
            rows.append(row_data)

    return rows


def verify_loan_portfolio_risk_scoring(traj, env_info, task_info):
    """
    Verify loan portfolio risk scoring model completion.

    Scoring (100 pts total, pass threshold: 65):
      25 pts — PMT formulas correct (>=15/20 within 2%)
      15 pts — Risk scores in valid range 3.0-13.5 (>=14/20)
      25 pts — Risk categories correctly assigned (>=14/20 match)
      15 pts — Expected loss column populated (>=14/20 non-zero)
      10 pts — Portfolio Summary sheet has non-zero values
      10 pts — File saved (output file exists)
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/loan_risk_result.json')
    pass_threshold = metadata.get('pass_threshold', 65)

    score = 0
    subscores = {}
    feedback_parts = []

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export file not found: {e}",
            "subscores": {},
        }

    try:
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse export result: {e}",
            "subscores": {},
        }
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    # --- Criterion: File saved ---
    output_exists = result.get('output_file_exists', False)
    if output_exists:
        score += 10
        subscores['file_saved'] = True
        feedback_parts.append("PASS: Output file saved (+10)")
    else:
        subscores['file_saved'] = False
        feedback_parts.append("FAIL: Output file not found — task not completed")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    parsed_data = result.get('parsed_data', {})
    if not parsed_data or parsed_data.get('error'):
        return {
            "passed": False,
            "score": score,
            "feedback": f"Could not parse spreadsheet: {parsed_data.get('error', 'unknown')}",
            "subscores": subscores,
        }

    loan_rows = parse_spreadsheet(parsed_data)

    if len(loan_rows) < 10:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Only {len(loan_rows)} loan rows found (expected 20) — formulas may not have been filled",
            "subscores": subscores,
        }

    # --- Criterion: PMT correctness ---
    pmt_correct = 0
    for i, row in enumerate(loan_rows[:20]):
        pmt_val = row.get('MonthlyPayment')
        if pmt_val is None:
            continue
        try:
            pmt_float = float(pmt_val)
            if pmt_float < 0:
                pmt_float = abs(pmt_float)
        except (TypeError, ValueError):
            continue
        if i < len(GROUND_TRUTH):
            expected_pmt = GROUND_TRUTH[i]['pmt']
            if abs(pmt_float - expected_pmt) / expected_pmt <= 0.02:
                pmt_correct += 1

    if pmt_correct >= 15:
        score += 25
        subscores['pmt_correct'] = True
        feedback_parts.append(f"PASS: PMT formulas correct ({pmt_correct}/20) (+25)")
    elif pmt_correct >= 8:
        partial = int(25 * pmt_correct / 20)
        score += partial
        subscores['pmt_correct'] = False
        feedback_parts.append(f"PARTIAL: PMT formulas ({pmt_correct}/20 correct) (+{partial})")
    else:
        subscores['pmt_correct'] = False
        feedback_parts.append(f"FAIL: PMT formulas only {pmt_correct}/20 correct")

    # --- Criterion: Risk scores in valid range ---
    risk_scores_valid = 0
    risk_scores_correct = 0
    categories_correct = 0
    el_populated = 0

    for i, row in enumerate(loan_rows[:20]):
        # Risk score validity
        rs_val = row.get('RiskScore')
        if rs_val is not None:
            try:
                rs_float = float(rs_val)
                if 3.0 <= rs_float <= 13.5:
                    risk_scores_valid += 1
                    if i < len(GROUND_TRUTH):
                        expected_rs = GROUND_TRUTH[i]['risk_score']
                        if abs(rs_float - expected_rs) <= 0.5:
                            risk_scores_correct += 1
            except (TypeError, ValueError):
                pass

        # Risk category
        cat_val = row.get('RiskCategory')
        if cat_val is not None and i < len(GROUND_TRUTH):
            cat_str = str(cat_val).strip().lower()
            expected_cat = GROUND_TRUTH[i]['category'].lower()
            if cat_str == expected_cat or expected_cat in cat_str:
                categories_correct += 1

        # Expected loss
        el_val = row.get('ExpectedLoss')
        if el_val is not None:
            try:
                el_float = float(el_val)
                if el_float > 0:
                    el_populated += 1
            except (TypeError, ValueError):
                pass

    if risk_scores_valid >= 14:
        score += 15
        subscores['risk_scores_valid'] = True
        feedback_parts.append(f"PASS: Risk scores in valid range ({risk_scores_valid}/20) (+15)")
    else:
        subscores['risk_scores_valid'] = False
        feedback_parts.append(f"FAIL: Only {risk_scores_valid}/20 risk scores in valid range 3.0-13.5")

    if categories_correct >= 14:
        score += 25
        subscores['categories_correct'] = True
        feedback_parts.append(f"PASS: Risk categories correct ({categories_correct}/20) (+25)")
    elif categories_correct >= 8:
        partial = int(25 * categories_correct / 20)
        score += partial
        subscores['categories_correct'] = False
        feedback_parts.append(f"PARTIAL: Risk categories ({categories_correct}/20 correct) (+{partial})")
    else:
        subscores['categories_correct'] = False
        feedback_parts.append(f"FAIL: Only {categories_correct}/20 risk categories correct")

    if el_populated >= 14:
        score += 15
        subscores['expected_loss_populated'] = True
        feedback_parts.append(f"PASS: Expected loss populated ({el_populated}/20) (+15)")
    else:
        subscores['expected_loss_populated'] = False
        feedback_parts.append(f"FAIL: Only {el_populated}/20 expected loss cells populated")

    # --- Criterion: Portfolio Summary sheet ---
    sheets = parsed_data.get('sheets', {})
    summary_sheet = sheets.get('Portfolio Summary', sheets.get('Summary', None))
    summary_has_values = False
    if summary_sheet:
        for row in summary_sheet:
            if row:
                for cell in row:
                    if cell is not None and str(cell).strip() not in ('', '0'):
                        try:
                            v = float(str(cell).replace(',', ''))
                            if v > 0:
                                summary_has_values = True
                                break
                        except ValueError:
                            pass
                if summary_has_values:
                    break

    if summary_has_values:
        score += 10
        subscores['portfolio_summary'] = True
        feedback_parts.append("PASS: Portfolio Summary sheet has values (+10)")
    else:
        subscores['portfolio_summary'] = False
        feedback_parts.append("FAIL: Portfolio Summary sheet is empty or has no non-zero values")

    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "pass_threshold": pass_threshold,
            "loan_rows_found": len(loan_rows),
            "pmt_correct": pmt_correct,
            "risk_scores_valid": risk_scores_valid,
            "categories_correct": categories_correct,
            "el_populated": el_populated,
        },
    }
