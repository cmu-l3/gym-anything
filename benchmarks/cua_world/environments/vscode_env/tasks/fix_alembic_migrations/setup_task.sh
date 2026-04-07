#!/bin/bash
set -e
echo "=== Setting up Fix Database Migrations Task ==="

source /workspace/scripts/task_utils.sh

WORKSPACE_DIR="/home/ga/workspace/media_db"
sudo -u ga mkdir -p "$WORKSPACE_DIR/alembic/versions"
cd "$WORKSPACE_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Install dependencies
echo "Installing Python dependencies..."
pip3 install --no-cache-dir alembic sqlalchemy pytest > /dev/null 2>&1

# 1. Generate the Mock DB Creation Script
cat > "$WORKSPACE_DIR/create_db.py" << 'EOF'
import sqlite3
import os

db_path = "chinook.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE Customer (
    CustomerId INTEGER PRIMARY KEY AUTOINCREMENT,
    FirstName NVARCHAR(40) NOT NULL,
    LastName NVARCHAR(20) NOT NULL,
    Company NVARCHAR(80),
    Address NVARCHAR(70),
    City NVARCHAR(40),
    State NVARCHAR(40),
    Country NVARCHAR(40),
    PostalCode NVARCHAR(10),
    Phone NVARCHAR(24),
    Fax NVARCHAR(24),
    Email NVARCHAR(60) NOT NULL,
    SupportRepId INTEGER
)''')

c.execute('''CREATE TABLE Invoice (
    InvoiceId INTEGER PRIMARY KEY AUTOINCREMENT,
    CustomerId INTEGER NOT NULL,
    InvoiceDate DATETIME NOT NULL,
    BillingAddress NVARCHAR(70),
    BillingCity NVARCHAR(40),
    BillingState NVARCHAR(40),
    BillingCountry NVARCHAR(40),
    BillingPostalCode NVARCHAR(10),
    Total NUMERIC(10,2) NOT NULL,
    FOREIGN KEY (CustomerId) REFERENCES Customer (CustomerId)
)''')

# Insert data to ensure NOT NULL constraints and data migrations actually get tested
c.execute("INSERT INTO Customer (FirstName, LastName, Email, Fax) VALUES ('Luís', 'Gonçalves', 'luisg@embraer.com.br', '+55 (12) 3923-5566')")
c.execute("INSERT INTO Customer (FirstName, LastName, Email, Fax) VALUES ('Leonie', 'Köhler', 'leonekohler@surfeu.de', '+49 0711 2842223')")

c.execute("INSERT INTO Invoice (CustomerId, InvoiceDate, Total) VALUES (1, '2009-01-01 00:00:00', 1.98)")
c.execute("INSERT INTO Invoice (CustomerId, InvoiceDate, Total) VALUES (2, '2009-01-02 00:00:00', 3.96)")
c.execute("INSERT INTO Invoice (CustomerId, InvoiceDate, Total) VALUES (1, '2010-01-03 00:00:00', 5.94)")

conn.commit()
conn.close()
EOF

# Execute the script to build initial DB state
sudo -u ga python3 "$WORKSPACE_DIR/create_db.py"

# 2. Setup Alembic Configuration
cat > "$WORKSPACE_DIR/alembic.ini" << 'EOF'
[alembic]
script_location = alembic
sqlalchemy.url = sqlite:///chinook.db
[loggers]
keys = root,sqlalchemy,alembic
[handlers]
keys = console
[formatters]
keys = generic
[logger_root]
level = WARN
handlers = console
qualname =
[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine
[logger_alembic]
level = INFO
handlers =
qualname = alembic
[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic
[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
EOF

cat > "$WORKSPACE_DIR/alembic/env.py" << 'EOF'
from logging.config import fileConfig
from sqlalchemy import engine_from_config
from sqlalchemy import pool
from alembic import context

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)
target_metadata = None

def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True, dialect_opts={"paramstyle": "named"})
    with context.begin_transaction():
        context.run_migrations()

def run_migrations_online() -> None:
    connectable = engine_from_config(config.get_section(config.config_ini_section, {}), prefix="sqlalchemy.", poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata, render_as_batch=True)
        with context.begin_transaction():
            context.run_migrations()

if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
EOF

# 3. Create Buggy Migration Script
cat > "$WORKSPACE_DIR/alembic/versions/a1b2c3d4_update_schema.py" << 'EOF'
"""update schema

Revision ID: a1b2c3d4
Revises: 
Create Date: 2024-05-20 10:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

revision = 'a1b2c3d4'
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    # 1. Add IsPremium to Customer (BUG: NOT NULL constraint fails on populated table)
    op.add_column('Customer', sa.Column('IsPremium', sa.Boolean(), nullable=False))

    # 2. Drop Fax from Customer (BUG: SQLite does not natively support DROP COLUMN without batch operations)
    op.drop_column('Customer', 'Fax')

    # 3. Add InvoiceYear to Invoice and populate it
    op.add_column('Invoice', sa.Column('InvoiceYear', sa.Integer(), nullable=True))
    # BUG: SQLite SUBSTR is 1-indexed. SUBSTR(InvoiceDate, 0, 4) produces incorrect behavior.
    op.execute("UPDATE Invoice SET InvoiceYear = CAST(SUBSTR(InvoiceDate, 0, 4) AS INTEGER)")

    # 4. Create CustomerLog table (BUG: Foreign key references non-existent 'Id' column instead of 'CustomerId')
    op.create_table('CustomerLog',
        sa.Column('LogId', sa.Integer(), nullable=False),
        sa.Column('CustomerId', sa.Integer(), nullable=False),
        sa.Column('Action', sa.String(length=50), nullable=False),
        sa.Column('Timestamp', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['CustomerId'], ['Customer.Id']),
        sa.PrimaryKeyConstraint('LogId')
    )

def downgrade():
    # BUG: Missing downgrade operations to reverse the schema changes.
    pass
EOF

# 4. Provide local test suite for agent
cat > "$WORKSPACE_DIR/test_migration.py" << 'EOF'
import pytest
import sqlite3
import subprocess
import os

def reset_db():
    subprocess.run(["python3", "create_db.py"], check=True)

def run_upgrade():
    return subprocess.run(["alembic", "upgrade", "head"], capture_output=True, text=True)

def run_downgrade():
    return subprocess.run(["alembic", "downgrade", "base"], capture_output=True, text=True)

def test_migration_lifecycle():
    reset_db()
    
    # 1. Test Upgrade
    res_up = run_upgrade()
    assert res_up.returncode == 0, f"Upgrade failed:\n{res_up.stderr}"
    
    # 2. Verify Schema & Data Post-Upgrade
    conn = sqlite3.connect("chinook.db")
    c = conn.cursor()
    
    # Check IsPremium and Fax on Customer
    columns = [col[1] for col in c.execute("PRAGMA table_info(Customer)").fetchall()]
    assert "IsPremium" in columns, "IsPremium column missing"
    assert "Fax" not in columns, "Fax column not dropped successfully"
    
    # Check Data migration (InvoiceYear extraction)
    c.execute("SELECT COUNT(*) FROM Invoice WHERE InvoiceYear = 2009")
    count_2009 = c.fetchone()[0]
    assert count_2009 == 2, f"Data migration failed: expected 2 invoices in 2009, got {count_2009}"
    
    # Check CustomerLog FK
    fks = c.execute("PRAGMA foreign_key_list(CustomerLog)").fetchall()
    assert len(fks) > 0, "CustomerLog missing foreign key"
    assert fks[0][4] == "CustomerId", f"CustomerLog FK references wrong column: {fks[0][4]}"
    
    # 3. Test Downgrade
    res_down = run_downgrade()
    assert res_down.returncode == 0, f"Downgrade failed:\n{res_down.stderr}"
    
    # 4. Verify Schema Post-Downgrade
    columns = [col[1] for col in c.execute("PRAGMA table_info(Customer)").fetchall()]
    assert "IsPremium" not in columns, "IsPremium column should be removed in downgrade"
    assert "Fax" in columns, "Fax column should be restored in downgrade"
    
    tables = [t[0] for t in c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    assert "CustomerLog" not in tables, "CustomerLog table not dropped in downgrade"
    
    conn.close()

if __name__ == "__main__":
    pytest.main(["-v", "test_migration.py"])
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# Launch VSCode
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    echo "Starting VSCode..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Wait and maximize
wait_for_window "Visual Studio Code" 30 || true
focus_vscode_window 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Open the buggy migration script
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/alembic/versions/a1b2c3d4_update_schema.py" 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="