#!/bin/bash
set -e
echo "=== Setting up fix_gdpr_data_cleaner ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/PycharmProjects/gdpr_cleaner"

# 1. Clean previous runs
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/cleaner"
mkdir -p "$PROJECT_DIR/tests"

# 2. Generate Data Generation Script (Realistic Dirty Data)
cat > "$PROJECT_DIR/generate_data.py" << 'EOF'
import csv
import random
import datetime

def random_phone():
    formats = [
        "{}-{}-{}", "({}) {}-{}", "{}.{}.{}", "{} {} {}", "+1-{}-{}-{}"
    ]
    fmt = random.choice(formats)
    return fmt.format(random.randint(200, 999), random.randint(200, 999), random.randint(1000, 9999))

def random_date():
    start = datetime.date(2020, 1, 1)
    end = datetime.date(2023, 12, 31)
    d = start + datetime.timedelta(days=random.randint(0, (end - start).days))
    # Mix formats to cause parsing issues
    if random.random() < 0.5:
        return d.strftime("%Y-%m-%d")
    else:
        return d.strftime("%m/%d/%Y")

def random_ip():
    return f"{random.randint(1,255)}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(0,255)}"

print("Generating raw_signups.csv...")
with open("data/raw_signups.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["id", "full_name", "email", "phone", "signup_date", "last_ip", "notes"])
    
    for i in range(1, 501):
        # Inject complexity
        phone = random_phone()
        date = random_date()
        ip = random_ip()
        email = f"user{i}@example.com"
        
        # 5% truly invalid data (to test robust handling)
        if random.random() < 0.05:
            date = "invalid-date"
            
        writer.writerow([i, f"User {i}", email, phone, date, ip, ""])
EOF

# 3. Create Source Code (The Buggy Version)

# cleaner/processors.py
cat > "$PROJECT_DIR/cleaner/processors.py" << 'EOF'
import hashlib
import re

def hash_email(email):
    """
    Anonymize email using a hash function.
    TODO: Ensure this is stable across runs for data warehouse joins.
    """
    if not isinstance(email, str):
        return ""
    # BUG: hash() is randomized in Python 3. Joins will break.
    return str(hash(email.strip().lower()))

def mask_ip(ip_address):
    """
    Mask the last octet of an IP address (e.g., 192.168.1.5 -> 192.168.1.xxx)
    Preserves geo-location accuracy while protecting privacy.
    """
    if not isinstance(ip_address, str) or not ip_address:
        return "0.0.0.0"
    
    parts = ip_address.split('.')
    if len(parts) != 4:
        return ip_address
        
    # BUG: This masks the last TWO octets (192.168.xxx.xxx) or constructs incorrectly
    # Requirement is 192.168.1.xxx
    return f"{parts[0]}.{parts[1]}.xxx.xxx"

def normalize_phone(phone):
    """
    Standardize phone numbers to XXX-XXX-XXXX format.
    Returns None if invalid, which causes the row to be dropped.
    """
    if not isinstance(phone, str):
        return None
        
    # BUG: Too strict. Fails on (555) 123-4567 or 555.123.4567
    pattern = r'^(\d{3})[-](\d{3})[-](\d{4})$'
    match = re.match(pattern, phone.strip())
    
    if match:
        return f"{match.group(1)}-{match.group(2)}-{match.group(3)}"
    
    return None
EOF

# cleaner/utils.py
cat > "$PROJECT_DIR/cleaner/utils.py" << 'EOF'
import pandas as pd

def parse_dates(date_series):
    """
    Convert a series of date strings to datetime objects.
    """
    # BUG: Hardcoded format fails on mixed data (MM/DD/YYYY vs YYYY-MM-DD)
    # Should use format='mixed' or let pandas infer
    return pd.to_datetime(date_series, format='%Y-%m-%d', errors='coerce')
EOF

# cleaner/__init__.py
touch "$PROJECT_DIR/cleaner/__init__.py"

# main.py
cat > "$PROJECT_DIR/main.py" << 'EOF'
import pandas as pd
import os
from cleaner.processors import hash_email, mask_ip, normalize_phone
from cleaner.utils import parse_dates

def run_pipeline():
    print("Loading data...")
    input_path = os.path.join(os.path.dirname(__file__), "data/raw_signups.csv")
    output_path = os.path.join(os.path.dirname(__file__), "data/clean_signups.csv")
    
    df = pd.read_csv(input_path)
    initial_count = len(df)
    
    print("Processing dates...")
    df['signup_date'] = parse_dates(df['signup_date'])
    
    print("Anonymizing emails...")
    df['email_hash'] = df['email'].apply(hash_email)
    
    print("Masking IPs...")
    df['last_ip'] = df['last_ip'].apply(mask_ip)
    
    print("Normalizing phones...")
    df['phone_clean'] = df['phone'].apply(normalize_phone)
    
    # Drop rows where phone number was invalid (returned None)
    df_clean = df.dropna(subset=['phone_clean']).copy()
    
    final_count = len(df_clean)
    dropped = initial_count - final_count
    
    print(f"Pipeline complete. Rows: {initial_count} -> {final_count} (Dropped {dropped})")
    
    df_clean.to_csv(output_path, index=False)

if __name__ == "__main__":
    run_pipeline()
EOF

# tests/conftest.py
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import pandas as pd

@pytest.fixture
def sample_data():
    return pd.DataFrame({
        'email': ['test@example.com', 'ALICE@EXAMPLE.COM'],
        'phone': ['123-456-7890', '(555) 123-4567'],
        'ip': ['192.168.1.5', '10.0.0.1'],
        'date': ['2023-01-01', '01/31/2023']
    })
EOF

# tests/test_hashing.py
cat > "$PROJECT_DIR/tests/test_hashing.py" << 'EOF'
import pytest
import hashlib
from cleaner.processors import hash_email

def test_hash_is_stable():
    """Hash should be deterministic (SHA256), not random (hash())."""
    email = "test@example.com"
    h1 = hash_email(email)
    
    # In a real test we can't easily restart python to prove non-determinism of hash(),
    # but we can verify it doesn't match the built-in hash() of the current process.
    assert h1 != str(hash(email.strip().lower())), "Should not use built-in hash()"
    
    # Check consistency for case sensitivity
    h2 = hash_email("TEST@EXAMPLE.COM")
    assert h1 == h2, "Hash should be case-insensitive"

def test_hash_format():
    val = hash_email("foo")
    # SHA256 hex digest is 64 chars
    assert len(val) >= 32, "Hash seems too short to be a secure hash"
    assert all(c in '0123456789abcdef' for c in val), "Hash should be hex string"
EOF

# tests/test_masking.py
cat > "$PROJECT_DIR/tests/test_masking.py" << 'EOF'
from cleaner.processors import mask_ip

def test_ip_masking_last_octet():
    ip = "192.168.1.55"
    # Should keep first 3 octets
    expected = "192.168.1.xxx"
    assert mask_ip(ip) == expected

def test_ip_masking_ignores_short():
    assert mask_ip("invalid") == "invalid"
EOF

# tests/test_normalization.py
cat > "$PROJECT_DIR/tests/test_normalization.py" << 'EOF'
from cleaner.processors import normalize_phone

def test_standard_format():
    assert normalize_phone("123-456-7890") == "123-456-7890"

def test_parentheses_format():
    # This currently fails (returns None)
    assert normalize_phone("(555) 123-4567") == "555-123-4567"

def test_dot_format():
    # This currently fails
    assert normalize_phone("555.123.4567") == "555-123-4567"

def test_space_format():
    assert normalize_phone("555 123 4567") == "555-123-4567"
EOF

# tests/test_dates.py
cat > "$PROJECT_DIR/tests/test_dates.py" << 'EOF'
import pandas as pd
from cleaner.utils import parse_dates

def test_mixed_date_formats():
    series = pd.Series(['2023-01-01', '01/31/2023', '2023-03-15'])
    result = parse_dates(series)
    
    assert not result.isna().any(), "Should parse all valid dates (no NaT)"
    assert result.dt.year.tolist() == [2023, 2023, 2023]
    assert result.dt.month.tolist() == [1, 1, 3]
    assert result.dt.day.tolist() == [1, 31, 15]
EOF

# 4. Generate the Data
cd "$PROJECT_DIR" && python3 generate_data.py
rm generate_data.py

# 5. Set ownership and install dependencies
chown -R ga:ga "$PROJECT_DIR"

echo "Installing project dependencies..."
pip3 install pandas pytest > /dev/null 2>&1

# 6. Launch PyCharm with the project
setup_pycharm_project "$PROJECT_DIR" "gdpr_cleaner" 120

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="