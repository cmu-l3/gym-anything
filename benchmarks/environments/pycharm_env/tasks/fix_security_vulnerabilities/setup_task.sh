#!/bin/bash
echo "=== Setting up fix_security_vulnerabilities ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_security_vulnerabilities"
PROJECT_DIR="/home/ga/PycharmProjects/inventory_api"

# Clean up any previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_start_ts
rm -f /tmp/${TASK_NAME}_result.json

# Create project structure
mkdir -p "$PROJECT_DIR/app"
mkdir -p "$PROJECT_DIR/tests"

# requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'REQUIREMENTS'
fastapi>=0.104.0
uvicorn>=0.24.0
pyjwt>=2.8.0
passlib[bcrypt]>=1.7.4
pytest>=7.0
httpx>=0.25.0
pytest-asyncio>=0.21.0
REQUIREMENTS

# --- app/__init__.py ---
touch "$PROJECT_DIR/app/__init__.py"

# --- app/database.py ---
# Uses SQLite in-memory for portability; real deployments would use PostgreSQL
cat > "$PROJECT_DIR/app/database.py" << 'PYEOF'
import sqlite3
import threading

_local = threading.local()


def get_db():
    """Return a per-thread SQLite connection."""
    if not hasattr(_local, "conn") or _local.conn is None:
        _local.conn = sqlite3.connect(":memory:", check_same_thread=False)
        _local.conn.row_factory = sqlite3.Row
        _init_db(_local.conn)
    return _local.conn


def _init_db(conn):
    cur = conn.cursor()
    cur.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'viewer'
        );

        CREATE TABLE IF NOT EXISTS items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            owner_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            sku TEXT UNIQUE NOT NULL,
            quantity INTEGER NOT NULL DEFAULT 0,
            location TEXT NOT NULL DEFAULT 'WAREHOUSE-A',
            FOREIGN KEY (owner_id) REFERENCES users(id)
        );

        INSERT OR IGNORE INTO users (id, username, password_hash, role)
        VALUES
            (1, 'admin', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQyCMRe2GMQ8bIiHqoNr1OmE2', 'admin'),
            (2, 'alice', '$2b$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'viewer'),
            (3, 'bob',   '$2b$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'viewer');

        INSERT OR IGNORE INTO items (id, owner_id, name, sku, quantity, location)
        VALUES
            (1, 2, 'Widget A',    'SKU-001', 150, 'RACK-A1'),
            (2, 2, 'Widget B',    'SKU-002', 75,  'RACK-A2'),
            (3, 3, 'Gadget X',    'SKU-003', 30,  'RACK-B1'),
            (4, 3, 'Gadget Y',    'SKU-004', 200, 'RACK-B2'),
            (5, 1, 'Admin Stock', 'SKU-005', 500, 'RACK-C1');
    """)
    conn.commit()
PYEOF

# --- app/auth.py ---
# VULNERABILITY 1: JWT_SECRET is hardcoded (should come from environment variable)
# VULNERABILITY 2 is in items.py (SQL injection)
cat > "$PROJECT_DIR/app/auth.py" << 'PYEOF'
import jwt
from datetime import datetime, timedelta, timezone
from passlib.context import CryptContext
from fastapi import HTTPException, Header
from app.database import get_db

# SECURITY ISSUE: Secret key is hardcoded in source code.
# Anyone with repository access can forge tokens.
JWT_SECRET = "supersecretkey123"
JWT_ALGORITHM = "HS256"
TOKEN_EXPIRE_MINUTES = 60

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(user_id: int, username: str, role: str) -> str:
    payload = {
        "sub": str(user_id),
        "username": username,
        "role": role,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


def get_current_user(authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    token = authorization[len("Bearer "):]
    return decode_token(token)


def authenticate_user(username: str, password: str):
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM users WHERE username = ?", (username,))
    user = cur.fetchone()
    if not user or not verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return dict(user)
PYEOF

# --- app/items.py ---
# VULNERABILITY 2: SQL injection in search_items (f-string used in query)
# VULNERABILITY 3: IDOR in get_item — no ownership check, any authenticated user can read any item
# VULNERABILITY 4: Path traversal in export_item_report (location field used in file path)
cat > "$PROJECT_DIR/app/items.py" << 'PYEOF'
import os
from fastapi import APIRouter, Depends, HTTPException
from app.auth import get_current_user
from app.database import get_db

router = APIRouter(prefix="/items", tags=["items"])

REPORTS_BASE_DIR = "/tmp/inventory_reports"


@router.get("/search")
def search_items(q: str, current_user: dict = Depends(get_current_user)):
    """Search items by name. Returns items owned by current user."""
    db = get_db()
    cur = db.cursor()
    owner_id = int(current_user["sub"])
    # SECURITY ISSUE: SQL injection — user-controlled `q` is interpolated directly
    # into the query string without parameterization.
    query = f"SELECT * FROM items WHERE owner_id = {owner_id} AND name LIKE '%{q}%'"
    cur.execute(query)
    rows = cur.fetchall()
    return [dict(r) for r in rows]


@router.get("/{item_id}")
def get_item(item_id: int, current_user: dict = Depends(get_current_user)):
    """Get a single inventory item by ID."""
    db = get_db()
    cur = db.cursor()
    # SECURITY ISSUE: IDOR — fetches item without checking that item belongs to current_user.
    # Any authenticated user can retrieve any other user's inventory item by guessing IDs.
    cur.execute("SELECT * FROM items WHERE id = ?", (item_id,))
    item = cur.fetchone()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return dict(item)


@router.get("/{item_id}/report")
def export_item_report(item_id: int, current_user: dict = Depends(get_current_user)):
    """Export a text report for an item to a file under REPORTS_BASE_DIR."""
    db = get_db()
    cur = db.cursor()
    owner_id = int(current_user["sub"])
    cur.execute("SELECT * FROM items WHERE id = ? AND owner_id = ?", (item_id, owner_id))
    item = cur.fetchone()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found or not owned by you")
    item = dict(item)

    # SECURITY ISSUE: Path traversal — item["location"] comes from the database but was set
    # by a user at creation time. An attacker can set location = "../../etc/passwd" and this
    # code will write a report to an arbitrary path outside REPORTS_BASE_DIR.
    os.makedirs(REPORTS_BASE_DIR, exist_ok=True)
    report_path = os.path.join(REPORTS_BASE_DIR, item["location"], f"item_{item_id}.txt")
    os.makedirs(os.path.dirname(report_path), exist_ok=True)

    with open(report_path, "w") as f:
        f.write(f"Item Report\n===========\n")
        f.write(f"ID:       {item['id']}\n")
        f.write(f"Name:     {item['name']}\n")
        f.write(f"SKU:      {item['sku']}\n")
        f.write(f"Quantity: {item['quantity']}\n")
        f.write(f"Location: {item['location']}\n")

    return {"report_path": report_path, "status": "generated"}
PYEOF

# --- app/main.py ---
cat > "$PROJECT_DIR/app/main.py" << 'PYEOF'
from fastapi import FastAPI
from pydantic import BaseModel
from app.auth import authenticate_user, create_access_token
from app.items import router as items_router

app = FastAPI(title="Inventory Management API", version="1.0.0")
app.include_router(items_router)


class LoginRequest(BaseModel):
    username: str
    password: str


@app.post("/auth/login")
def login(req: LoginRequest):
    user = authenticate_user(req.username, req.password)
    token = create_access_token(user["id"], user["username"], user["role"])
    return {"access_token": token, "token_type": "bearer"}


@app.get("/health")
def health():
    return {"status": "ok"}
PYEOF

# --- tests/__init__.py ---
touch "$PROJECT_DIR/tests/__init__.py"

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth import create_access_token


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def alice_token():
    return create_access_token(2, "alice", "viewer")


@pytest.fixture
def bob_token():
    return create_access_token(3, "bob", "viewer")


@pytest.fixture
def admin_token():
    return create_access_token(1, "admin", "admin")
PYEOF

# --- tests/test_auth.py ---
cat > "$PROJECT_DIR/tests/test_auth.py" << 'PYEOF'
def test_login_success(client):
    resp = client.post("/auth/login", json={"username": "alice", "password": "password"})
    assert resp.status_code == 200
    assert "access_token" in resp.json()


def test_login_wrong_password(client):
    resp = client.post("/auth/login", json={"username": "alice", "password": "wrong"})
    assert resp.status_code == 401


def test_protected_endpoint_without_token(client):
    resp = client.get("/items/1")
    assert resp.status_code == 422  # missing required header


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
PYEOF

# --- tests/test_items.py ---
cat > "$PROJECT_DIR/tests/test_items.py" << 'PYEOF'
def test_search_own_items(client, alice_token):
    resp = client.get("/items/search?q=Widget",
                      headers={"Authorization": f"Bearer {alice_token}"})
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) >= 1
    assert all(i["owner_id"] == 2 for i in items)


def test_get_own_item(client, alice_token):
    resp = client.get("/items/1", headers={"Authorization": f"Bearer {alice_token}"})
    assert resp.status_code == 200
    assert resp.json()["id"] == 1


def test_get_item_not_found(client, alice_token):
    resp = client.get("/items/9999", headers={"Authorization": f"Bearer {alice_token}"})
    assert resp.status_code == 404


def test_search_returns_only_own_items(client, alice_token):
    """Alice should not see Bob's items in search results."""
    resp = client.get("/items/search?q=Gadget",
                      headers={"Authorization": f"Bearer {alice_token}"})
    assert resp.status_code == 200
    items = resp.json()
    # All returned items must belong to Alice (owner_id=2)
    assert all(i["owner_id"] == 2 for i in items)
PYEOF

# --- tests/test_security.py ---
# These tests verify the vulnerabilities are FIXED (they will fail until fixes are applied)
cat > "$PROJECT_DIR/tests/test_security.py" << 'PYEOF'
import os
import re
import pytest


# ----- Test 1: JWT secret must NOT be hardcoded -----
def test_jwt_secret_not_hardcoded():
    """JWT_SECRET must be loaded from environment variable, not a literal string."""
    with open("app/auth.py") as f:
        source = f.read()
    # Must not contain a hardcoded string assignment to JWT_SECRET
    # Acceptable patterns: os.environ["JWT_SECRET"], os.getenv("JWT_SECRET"), os.environ.get(...)
    assert re.search(r'JWT_SECRET\s*=\s*os\.environ', source) or \
           re.search(r'JWT_SECRET\s*=\s*os\.getenv', source), \
        "JWT_SECRET must be loaded from an environment variable, not hardcoded"
    # Must not contain the literal bad secret
    assert "supersecretkey123" not in source, \
        "Hardcoded JWT secret 'supersecretkey123' still present in source"


# ----- Test 2: SQL injection fixed in search endpoint -----
def test_sql_injection_fixed():
    """search_items must use parameterized queries, not f-strings or % formatting."""
    with open("app/items.py") as f:
        source = f.read()
    # The vulnerable pattern: f"... LIKE '%{q}%'"
    assert "LIKE '%" + "{q}" not in source and "LIKE '%" + "{" not in source, \
        "SQL injection pattern (f-string query with user input) still present in items.py"
    # The safe pattern should use a parameterized placeholder
    assert re.search(r"LIKE\s+['\"]%\?%['\"]|LIKE\s+\?|\?,", source), \
        "Parameterized query placeholder (?) not found in search_items"


# ----- Test 3: IDOR fixed — get_item checks ownership -----
def test_idor_fixed(client, alice_token, bob_token):
    """Alice must not be able to access Bob's items (owner_id=3)."""
    # Item 3 belongs to Bob (owner_id=3); Alice (owner_id=2) must get 403 or 404
    resp = client.get("/items/3", headers={"Authorization": f"Bearer {alice_token}"})
    assert resp.status_code in (403, 404), \
        f"IDOR not fixed: Alice received status {resp.status_code} accessing Bob's item"


# ----- Test 4: Path traversal fixed in report endpoint -----
def test_path_traversal_fixed():
    """export_item_report must validate/sanitize the location field to prevent path traversal."""
    with open("app/items.py") as f:
        source = f.read()
    # Must contain a check that prevents traversal, e.g., os.path.abspath + startswith,
    # or os.path.basename, or an explicit ".." rejection
    has_abspath_check = "os.path.abspath" in source and "startswith" in source
    has_basename = "os.path.basename" in source
    has_traversal_guard = re.search(r'[\'"]\.\.[\'"]|\.\..*in|replace.*\.\.', source) is not None
    has_realpath = "os.path.realpath" in source and "startswith" in source
    assert has_abspath_check or has_basename or has_traversal_guard or has_realpath, \
        "Path traversal fix not detected in export_item_report — location must be sanitized"
PYEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Install dependencies as ga user (needed for tests to run)
echo "Installing Python dependencies..."
su - ga -c "pip3 install --quiet fastapi uvicorn pyjwt 'passlib[bcrypt]' pytest httpx pytest-asyncio 2>&1 | tail -5" || true

# Create .idea PyCharm project files
mkdir -p "$PROJECT_DIR/.idea"
cat > "$PROJECT_DIR/.idea/misc.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectRootManager" version="2" project-jdk-name="Python 3.11" project-jdk-type="Python SDK" />
</project>
XML

cat > "$PROJECT_DIR/.idea/modules.xml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://$PROJECT_DIR$/inventory_api.iml" filepath="$PROJECT_DIR$/inventory_api.iml" />
    </modules>
  </component>
</project>
XML

cat > "$PROJECT_DIR/.idea/inventory_api.iml" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<module type="PYTHON_MODULE" version="4">
  <component name="NewModuleRootManager">
    <content url="file://$MODULE_DIR$" />
    <orderEntry type="inheritedJdk" />
    <orderEntry type="sourceFolder" forTests="false" />
  </component>
</module>
XML

chown -R ga:ga "$PROJECT_DIR/.idea"

# Record start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts

# Open in PyCharm
echo "Opening project in PyCharm..."
if type setup_pycharm_project &>/dev/null; then
    setup_pycharm_project "$PROJECT_DIR"
else
    su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' >> /home/ga/pycharm.log 2>&1 &"
    sleep 15
fi

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
