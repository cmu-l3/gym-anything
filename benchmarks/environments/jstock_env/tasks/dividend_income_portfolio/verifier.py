#!/usr/bin/env python3
"""
Verifier for dividend_income_portfolio task.

Task: Financial Manager creating an income portfolio with specific dividend stocks.
Required:
  Portfolio: 'Income Portfolio' (new, separate from My Portfolio)
  BUY T:  200 shares @ $17.11, Jan 15 2024, broker $9.99, comment contains 'high-yield telecom'
  BUY VZ: 150 shares @ $38.58, Jan 15 2024, broker $9.99, comment contains '5G income'
  BUY KO: 100 shares @ $58.02, Jan 15 2024, broker $9.99, comment contains 'dividend aristocrat'
  BUY O:   80 shares @ $53.10, Jan 15 2024, broker $9.99, comment contains 'monthly REIT'
  DIV T:  $55.50, Feb 1 2024,  comment: 'AT&T Q1 2024 quarterly dividend'
  DIV O:  $20.52, Feb 15 2024, comment: 'Realty Income Feb 2024 monthly distribution'
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/dividend_income_portfolio_result.json"

REQUIRED_BUYS = {
    "T":  {"units": 200.0, "price": 17.11, "date_substr": "Jan 15, 2024", "broker": 9.99, "comment_keyword": "high-yield telecom"},
    "VZ": {"units": 150.0, "price": 38.58, "date_substr": "Jan 15, 2024", "broker": 9.99, "comment_keyword": "5G income"},
    "KO": {"units": 100.0, "price": 58.02, "date_substr": "Jan 15, 2024", "broker": 9.99, "comment_keyword": "dividend aristocrat"},
    "O":  {"units":  80.0, "price": 53.10, "date_substr": "Jan 15, 2024", "broker": 9.99, "comment_keyword": "monthly REIT"},
}

REQUIRED_DIVS = {
    "T": {"amount": 55.50, "date_substr": "Feb 1, 2024",  "comment_keyword": "AT&T Q1"},
    "O": {"amount": 20.52, "date_substr": "Feb 15, 2024", "comment_keyword": "monthly"},
}

PRICE_TOL   = 0.15
UNITS_TOL   = 1.0
BROKER_TOL  = 0.10
AMOUNT_TOL  = 2.00


def _check_buy(entry, spec, code):
    """Check one buy entry. Returns (pts, max_pts=20, notes)."""
    if not entry:
        return 0, 20, [f"{code} buy entry not found"]
    pts = 0
    notes = []

    # Units: 4 pts
    try:
        units = float(entry.get("Units", "0") or "0")
        if abs(units - spec["units"]) <= UNITS_TOL:
            pts += 4
        else:
            notes.append(f"units {units} != {spec['units']}")
    except ValueError:
        notes.append("invalid units")

    # Price: 4 pts
    try:
        price = float(entry.get("Purchase Price", "0") or "0")
        if abs(price - spec["price"]) <= PRICE_TOL:
            pts += 4
        else:
            notes.append(f"price {price:.2f} != {spec['price']:.2f}")
    except ValueError:
        notes.append("invalid price")

    # Date: 4 pts
    date_val = entry.get("Date", "")
    if spec["date_substr"].lower() in date_val.lower():
        pts += 4
    else:
        notes.append(f"date '{date_val}' != '{spec['date_substr']}'")

    # Broker: 4 pts
    try:
        broker = float(entry.get("Broker", "0") or "0")
        if abs(broker - spec["broker"]) <= BROKER_TOL:
            pts += 4
        else:
            notes.append(f"broker {broker:.2f} != {spec['broker']:.2f}")
    except ValueError:
        notes.append("invalid broker")

    # Comment keyword: 4 pts
    comment = entry.get("Comment", "").lower()
    if spec["comment_keyword"].lower() in comment:
        pts += 4
    else:
        notes.append(f"comment missing '{spec['comment_keyword']}'")

    return pts, 20, notes


def _check_div(entry, spec, code):
    """Check one dividend entry. Returns (pts, max_pts, notes)."""
    max_pts = 7 if code == "T" else 8
    if not entry:
        return 0, max_pts, [f"{code} dividend entry not found"]
    pts = 0
    notes = []

    # Amount: max_pts-3 pts (4 for T, 5 for O)
    amount_pts = max_pts - 3
    try:
        amount = float(entry.get("Amount", "0") or "0")
        if abs(amount - spec["amount"]) <= AMOUNT_TOL:
            pts += amount_pts
        else:
            notes.append(f"amount {amount:.2f} != {spec['amount']:.2f}")
    except ValueError:
        notes.append("invalid amount")

    # Date: 1 pt
    date_val = entry.get("Date", "")
    if spec["date_substr"].lower() in date_val.lower():
        pts += 1
    else:
        notes.append(f"date '{date_val}' != '{spec['date_substr']}'")

    # Comment keyword: 2 pts
    comment = entry.get("Comment", "").lower()
    if spec["comment_keyword"].lower() in comment:
        pts += 2
    else:
        notes.append(f"comment missing '{spec['comment_keyword']}'")

    return pts, max_pts, notes


def verify_dividend_income_portfolio(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    result = {}
    if copy_from_env:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r", encoding="utf-8") as f:
                result = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load result JSON: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not read result file: {e}. Agent may not have completed the task.",
                "subscores": {}
            }
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass

    # ----------------------------------------------------------------
    # GATE: "Income Portfolio" must exist and have at least 1 buy entry
    # ----------------------------------------------------------------
    portfolio_exists = result.get("portfolio_exists", False)
    buy_count = result.get("buy_count", 0)

    if not portfolio_exists and buy_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: 'Income Portfolio' was not created. Agent may have added entries to wrong portfolio.",
            "subscores": {}
        }

    # ----------------------------------------------------------------
    # Score each transaction
    # ----------------------------------------------------------------
    total_score = 0
    feedback_parts = []
    subscores = {}

    # Portfolio exists: 5 pts
    if portfolio_exists:
        total_score += 5
        subscores["portfolio_created"] = 5
    else:
        subscores["portfolio_created"] = 0
        feedback_parts.append("Portfolio 'Income Portfolio': NOT CREATED")

    # Buy entries
    for code, spec in REQUIRED_BUYS.items():
        entry = result.get(f"buy_{code.lower()}")
        pts, max_pts, notes = _check_buy(entry, spec, code)
        total_score += pts
        subscores[f"buy_{code}"] = pts
        status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
        msg = f"BUY {code}: {status}"
        if notes:
            msg += f" ({', '.join(notes)})"
        feedback_parts.append(msg)

    # Dividend entries
    for code, spec in REQUIRED_DIVS.items():
        entry = result.get(f"div_{code.lower()}")
        max_pts = 7 if code == "T" else 8
        pts, max_pts, notes = _check_div(entry, spec, code)
        total_score += pts
        subscores[f"div_{code}"] = pts
        status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
        msg = f"DIV {code}: {status}"
        if notes:
            msg += f" ({', '.join(notes)})"
        feedback_parts.append(msg)

    total_score = min(total_score, 100)
    passed = total_score >= 60

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
