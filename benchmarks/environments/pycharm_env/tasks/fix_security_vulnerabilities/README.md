# fix_security_vulnerabilities

## Overview

**Occupation**: Information Security Engineers
**Industry**: Computer Systems Design and Related Services
**Difficulty**: Very Hard

A FastAPI-based inventory management REST API (`inventory_api`) has been flagged by the security team as containing multiple OWASP Top 10 vulnerabilities before it ships to production. The agent must audit the source code, identify all vulnerabilities, and fix them without breaking the existing functional test suite.

No information about which specific vulnerabilities exist or where they are is given to the agent. The agent must discover them by reading the code.

---

## Goal

Fix all security vulnerabilities in the `inventory_api` project such that:
1. All security tests in `tests/test_security.py` pass
2. All functional tests in `tests/test_auth.py` and `tests/test_items.py` continue to pass

---

## Starting State

The project is at `/home/ga/PycharmProjects/inventory_api/` and contains:

```
inventory_api/
├── app/
│   ├── auth.py       # Vuln 1: hardcoded JWT_SECRET
│   ├── items.py      # Vuln 2: SQL injection; Vuln 3: IDOR; Vuln 4: path traversal
│   ├── database.py   # SQLite in-memory database, no bugs
│   └── main.py       # FastAPI app entry point, no bugs
├── tests/
│   ├── conftest.py
│   ├── test_auth.py       # Functional tests (must still pass after fixes)
│   ├── test_items.py      # Functional tests (must still pass after fixes)
│   └── test_security.py   # Security tests (all 4 fail before fixes)
└── requirements.txt
```

**Initially failing tests**: all 4 in `test_security.py`

---

## Vulnerabilities (Ground Truth — do not reveal in task description)

| Vuln | File | Type | Description |
|------|------|------|-------------|
| 1 | `app/auth.py` | Hardcoded secret | `JWT_SECRET = "supersecretkey123"` — must load from `os.environ` |
| 2 | `app/items.py` | SQL injection | `search_items` builds query with f-string; must use parameterized `?` placeholder |
| 3 | `app/items.py` | IDOR | `get_item` fetches any item by ID without checking `owner_id == current_user` |
| 4 | `app/items.py` | Path traversal | `export_item_report` uses `item["location"]` directly in `os.path.join`; location could be `../../etc/passwd` |

---

## Verification Strategy

**Criterion 1 (25 pts)**: `vuln1_hardcoded_secret_fixed` — `JWT_SECRET` loaded from `os.environ` / `os.getenv`, literal `"supersecretkey123"` removed
**Criterion 2 (25 pts)**: `vuln2_sql_injection_fixed` — no f-string query interpolation; parameterized `?` placeholder used
**Criterion 3 (25 pts)**: `vuln3_idor_fixed` — `get_item` checks `owner_id` matches current user
**Criterion 4 (25 pts)**: `vuln4_path_traversal_fixed` — `export_item_report` uses `os.path.basename` or `abspath+startswith` check

**Pass threshold**: 60/100 (must fix at least 2-3 vulnerabilities)

---

## Schema Reference

```python
# users table: id, username, password_hash, role
# items table: id, owner_id, name, sku, quantity, location
# JWT payload: {"sub": str(user_id), "username": ..., "role": ..., "exp": ...}
```

---

## Edge Cases

- The functional tests must keep passing after fixes (no breaking changes to API behavior)
- Vuln 2 fix: parameterized query must still return correct results for the `owner_id` filter
- Vuln 3 fix: admin users querying other users' items is acceptable (role-based check optional)
- Vuln 4 fix: `os.path.basename()` is the simplest fix; `abspath+startswith(REPORTS_BASE_DIR)` also accepted
