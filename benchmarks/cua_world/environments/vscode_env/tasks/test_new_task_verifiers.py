#!/usr/bin/env python3
"""
Offline mock tests for all 5 new vscode_env tasks.

Tests three scenarios per task:
  1. Do-nothing (file missing) → passed=False, score=0
  2. Do-nothing (original buggy code) → passed=False
  3. Partial fix (some bugs fixed) → passed=False, 0 < score < 60
  4. Full fix (all bugs fixed) → passed=True, score >= 60

See task_creation_notes/13_file_content_verification_and_offline_testing.md
"""

import importlib.util
import json
import os
import sys
import tempfile

TASKS_DIR = os.path.dirname(os.path.abspath(__file__))

# ──────────────────────────────────────────────────────────
# Mock helpers (from Gap 2 pattern)
# ──────────────────────────────────────────────────────────

def load_verifier(task_name):
    """Load a verifier module from its file path."""
    path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location("verifier", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_env(result_data, result_path):
    """Create env_info with mocked copy_from_env that serves one result file."""
    def copy_from_env(src, dst):
        if src == result_path:
            with open(dst, "w", encoding="utf-8") as f:
                json.dump(result_data, f)
        else:
            # Hash files / other files → not available in mock
            raise FileNotFoundError(f"Mock: {src} not available")
    return {"copy_from_env": copy_from_env}


def make_env_missing():
    """Simulate export script never ran."""
    def copy_from_env(src, dst):
        raise FileNotFoundError(f"No such file: {src}")
    return {"copy_from_env": copy_from_env}


# ──────────────────────────────────────────────────────────
# Test data for each task
# ──────────────────────────────────────────────────────────

# ═══ 1. audit_clinical_trial_pipeline ═══

CLINICAL_BUGGY = {
    "config.py": "SIGNIFICANCE_LEVEL = 0.10\nOUTPUT_DIR = 'results'\n",
    "analysis/data_loader.py": (
        "import pandas as pd\n"
        "def load_data(path):\n"
        "    df = pd.read_csv(path)\n"
        "    df = df.dropna(subset=['secondary_endpoint'])\n"
        "    return df\n"
    ),
    "analysis/primary_endpoint.py": (
        "from scipy import stats\n"
        "def analyze(df):\n"
        "    stat, p = stats.ttest_ind(df['treatment'], df['control'], alternative='greater')\n"
        "    z_critical = 1.96\n"
        "    ci = (mean - z_critical * se, mean + z_critical * se)\n"
        "    return p, ci\n"
    ),
    "analysis/safety_analysis.py": (
        "def count_adverse_events(patients):\n"
        "    ae_counts = {}\n"
        "    for patient in patients:\n"
        "        patient_events = patient.get('adverse_events', [])\n"
        "        for event in patient_events:\n"
        "            term = event['term']\n"
        "            ae_counts[term] = ae_counts.get(term, 0)\n"
        "            ae_counts[term] += len(patient_events)\n"
        "    return ae_counts\n"
    ),
    "analysis/subgroup_analysis.py": (
        "from scipy import stats\n"
        "def analyze_subgroups(df, subgroups):\n"
        "    results = {}\n"
        "    for subgroup in subgroups:\n"
        "        sub_df = df[df['subgroup'] == subgroup]\n"
        "        stat, p_value = stats.ttest_ind(sub_df['treatment'], sub_df['control'])\n"
        "        results[subgroup] = {'p_value': p_value}\n"
        "    return results\n"
    ),
    "analysis/report_generator.py": "def generate_report(): pass\n",
    "run_analysis.py": "if __name__ == '__main__': pass\n",
}

CLINICAL_PARTIAL = {
    **CLINICAL_BUGGY,
    # Fix only 2 of 6: alpha + ITT = 17+16 = 33 points (below 60)
    "config.py": "SIGNIFICANCE_LEVEL = 0.05\nOUTPUT_DIR = 'results'\n",
    "analysis/data_loader.py": (
        "import pandas as pd\n"
        "def load_data(path):\n"
        "    df = pd.read_csv(path)\n"
        "    # ITT: keep all randomised patients\n"
        "    return df\n"
    ),
}

CLINICAL_FIXED = {
    **CLINICAL_PARTIAL,
    # Fix remaining 3: AE counting, multiplicity, (alpha + 2-sided + CI already fixed)
    "analysis/safety_analysis.py": (
        "def count_adverse_events(patients):\n"
        "    ae_counts = {}\n"
        "    for patient in patients:\n"
        "        patient_events = patient.get('adverse_events', [])\n"
        "        seen_terms = set()\n"
        "        for event in patient_events:\n"
        "            term = event['term']\n"
        "            if term not in seen_terms:\n"
        "                ae_counts[term] = ae_counts.get(term, 0)\n"
        "                ae_counts[term] += 1\n"
        "                seen_terms.add(term)\n"
        "    return ae_counts\n"
    ),
    "analysis/subgroup_analysis.py": (
        "from scipy import stats\n"
        "def analyze_subgroups(df, subgroups):\n"
        "    results = {}\n"
        "    n_comparisons = len(subgroups)\n"
        "    for subgroup in subgroups:\n"
        "        sub_df = df[df['subgroup'] == subgroup]\n"
        "        stat, p_value = stats.ttest_ind(sub_df['treatment'], sub_df['control'])\n"
        "        # Bonferroni correction\n"
        "        adjusted_p = p_value * n_comparisons\n"
        "        results[subgroup] = {'p_value': adjusted_p}\n"
        "    return results\n"
    ),
}


# ═══ 2. debug_distributed_payment_system ═══

PAYMENT_BUGGY = {
    "services/payment_processor.py": (
        "from services.currency_converter import CurrencyConverter\n"
        "class PaymentProcessor:\n"
        "    def process_payment(self, transaction):\n"
        "        amount = float(transaction['amount'])\n"
        "        fee = amount * 0.025\n"
        "        total = amount + fee\n"
        "        return {'total': total}\n"
    ),
    "services/currency_converter.py": (
        "class CurrencyConverter:\n"
        "    RATES = {'USD_EUR': 0.8547}\n"
        "    def convert(self, amount, src, tgt):\n"
        "        direct_key = f'{src}_{tgt}'\n"
        "        inverse_key = f'{tgt}_{src}'\n"
        "        if direct_key in self.RATES:\n"
        "            rate = self.RATES[direct_key]\n"
        "            return amount * rate\n"
        "        elif inverse_key in self.RATES:\n"
        "            rate = self.RATES[inverse_key]\n"
        "            return amount * rate\n"
    ),
    "services/transaction_validator.py": (
        "MAX_TRANSACTION_LIMIT = 1000000\n"
        "class TransactionValidator:\n"
        "    def validate(self, transaction):\n"
        "        amount = transaction['amount']\n"
        "        if amount > 0:\n"
        "            return {'valid': True, 'reason': None}\n"
        "        return {'valid': False, 'reason': 'Amount must be positive'}\n"
    ),
    "services/ledger.py": (
        "class Ledger:\n"
        "    def __init__(self):\n"
        "        self.balances = {'asset': 0.0, 'liability': 0.0}\n"
        "    def record_entry(self, transaction_id, amount, entry_type, account_type, description=''):\n"
        "        if entry_type == 'debit':\n"
        "            self.balances[account_type] += amount\n"
        "        elif entry_type == 'credit':\n"
        "            self.balances[account_type] -= amount\n"
    ),
    "services/idempotency.py": (
        "class IdempotencyStore:\n"
        "    def __init__(self):\n"
        "        self.keys = {}\n"
        "    def is_duplicate(self, key):\n"
        "        if not key:\n"
        "            return False\n"
        "        return key in self.keys\n"
        "    def store(self, key, transaction_id):\n"
        "        if not key:\n"
        "            return\n"
        "        self.keys[key] = {'transaction_id': transaction_id}\n"
    ),
}

PAYMENT_PARTIAL = {
    **PAYMENT_BUGGY,
    # Fix 2 of 5: Decimal and case-insensitive idempotency
    "services/payment_processor.py": (
        "from decimal import Decimal, ROUND_HALF_UP\n"
        "class PaymentProcessor:\n"
        "    def process_payment(self, transaction):\n"
        "        amount = Decimal(str(transaction['amount']))\n"
        "        fee = amount * Decimal('0.025')\n"
        "        total = amount + fee\n"
        "        return {'total': str(total)}\n"
    ),
    "services/idempotency.py": (
        "class IdempotencyStore:\n"
        "    def __init__(self):\n"
        "        self.keys = {}\n"
        "    def is_duplicate(self, key):\n"
        "        if not key:\n"
        "            return False\n"
        "        return key.lower() in self.keys\n"
        "    def store(self, key, transaction_id):\n"
        "        if not key:\n"
        "            return\n"
        "        self.keys[key.lower()] = {'transaction_id': transaction_id}\n"
    ),
}

PAYMENT_FIXED = {
    **PAYMENT_PARTIAL,
    "services/currency_converter.py": (
        "class CurrencyConverter:\n"
        "    RATES = {'USD_EUR': 0.8547}\n"
        "    def convert(self, amount, src, tgt):\n"
        "        direct_key = f'{src}_{tgt}'\n"
        "        inverse_key = f'{tgt}_{src}'\n"
        "        if direct_key in self.RATES:\n"
        "            rate = self.RATES[direct_key]\n"
        "            return amount * rate\n"
        "        elif inverse_key in self.RATES:\n"
        "            rate = self.RATES[inverse_key]\n"
        "            return amount / rate\n"
    ),
    "services/transaction_validator.py": (
        "MAX_TRANSACTION_LIMIT = 1000000\n"
        "class TransactionValidator:\n"
        "    def validate(self, transaction):\n"
        "        amount = transaction['amount']\n"
        "        if not isinstance(amount, (int, float)):\n"
        "            return {'valid': False, 'reason': 'Amount must be numeric'}\n"
        "        if amount <= 0:\n"
        "            return {'valid': False, 'reason': 'Amount must be positive'}\n"
        "        if amount > MAX_TRANSACTION_LIMIT:\n"
        "            return {'valid': False, 'reason': 'Amount exceeds limit'}\n"
        "        return {'valid': True, 'reason': None}\n"
    ),
    "services/ledger.py": (
        "class Ledger:\n"
        "    def __init__(self):\n"
        "        self.balances = {'asset': 0.0, 'liability': 0.0}\n"
        "    def record_entry(self, transaction_id, amount, entry_type, account_type, description=''):\n"
        "        if account_type == 'liability':\n"
        "            if entry_type == 'debit':\n"
        "                self.balances[account_type] -= amount\n"
        "            elif entry_type == 'credit':\n"
        "                self.balances[account_type] += amount\n"
        "        else:\n"
        "            if entry_type == 'debit':\n"
        "                self.balances[account_type] += amount\n"
        "            elif entry_type == 'credit':\n"
        "                self.balances[account_type] -= amount\n"
    ),
}


# ═══ 3. fix_geospatial_etl_pipeline ═══

GEOSPATIAL_BUGGY = {
    "transforms/coordinate_transform.py": (
        "def transform_coordinates(features, target_crs='EPSG:4326'):\n"
        "    transformed = []\n"
        "    for feature in features:\n"
        "        coords = feature['geometry']['coordinates']\n"
        "        new_coords = []\n"
        "        for coord in coords:\n"
        "            lat = coord[0]\n"
        "            lng = coord[1]\n"
        "            new_coords.append([lat, lng])\n"
        "        feature['geometry']['coordinates'] = new_coords\n"
        "        transformed.append(feature)\n"
        "    return transformed\n"
    ),
    "transforms/spatial_operations.py": (
        "import math\n"
        "def create_buffer(polygon_coords, distance_meters):\n"
        "    centroid = get_centroid(polygon_coords)\n"
        "    dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(centroid, polygon_coords[0])))\n"
        "    scale = (dist + distance_meters) / dist\n"
        "    return [[c[0] * scale, c[1] * scale] for c in polygon_coords]\n"
    ),
    "transforms/area_calculator.py": (
        "def calculate_area(polygon_coords):\n"
        "    n = len(polygon_coords)\n"
        "    area = 0.0\n"
        "    for i in range(n):\n"
        "        j = (i + 1) % n\n"
        "        area += polygon_coords[i][0] * polygon_coords[j][1]\n"
        "        area -= polygon_coords[j][0] * polygon_coords[i][1]\n"
        "    return abs(area) / 2.0\n"
    ),
    "transforms/topology_validator.py": (
        "def check_self_intersection(polygon):\n"
        "    segments = list(zip(polygon[:-1], polygon[1:]))\n"
        "    for i, (a, b) in enumerate(segments):\n"
        "        for j, (c, d) in enumerate(segments):\n"
        "            if abs(i - j) <= 1: continue\n"
        "            if _segments_intersect(a, b, c, d):\n"
        "                return True\n"
        "    return False\n"
        "def _segments_intersect(a, b, c, d):\n"
        "    d1 = (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])\n"
        "    d2 = (b[0]-a[0])*(d[1]-a[1]) - (b[1]-a[1])*(d[0]-a[0])\n"
        "    d3 = (d[0]-c[0])*(a[1]-c[1]) - (d[1]-c[1])*(a[0]-c[0])\n"
        "    d4 = (d[0]-c[0])*(b[1]-c[1]) - (d[1]-c[1])*(b[0]-c[0])\n"
        "    if d1 == 0 and d2 == 0:\n"
        "        return True\n"
        "    return (d1 * d2 < 0) and (d3 * d4 < 0)\n"
    ),
    "exporters/geojson_exporter.py": (
        "import json\n"
        "def export_features(features, output_path):\n"
        "    output = features\n"
        "    with open(output_path, 'w') as f:\n"
        "        json.dump(output, f, indent=2)\n"
    ),
}

GEOSPATIAL_PARTIAL = {
    **GEOSPATIAL_BUGGY,
    # Fix only 2 of 5: coord order + FeatureCollection = 40 pts (below 60)
    "transforms/coordinate_transform.py": (
        "def transform_coordinates(features, target_crs='EPSG:4326'):\n"
        "    transformed = []\n"
        "    for feature in features:\n"
        "        coords = feature['geometry']['coordinates']\n"
        "        new_coords = []\n"
        "        for coord in coords:\n"
        "            lng = coord[0]\n"
        "            lat = coord[1]\n"
        "            new_coords.append([lng, lat])\n"
        "        feature['geometry']['coordinates'] = new_coords\n"
        "        transformed.append(feature)\n"
        "    return transformed\n"
    ),
    "exporters/geojson_exporter.py": (
        "import json\n"
        "def export_features(features, output_path):\n"
        "    output = {'type': 'FeatureCollection', 'features': features}\n"
        "    with open(output_path, 'w') as f:\n"
        "        json.dump(output, f, indent=2)\n"
    ),
}

GEOSPATIAL_FIXED = {
    **GEOSPATIAL_PARTIAL,
    "transforms/spatial_operations.py": (
        "import math\n"
        "def create_buffer(polygon_coords, distance_meters):\n"
        "    centroid = get_centroid(polygon_coords)\n"
        "    lat_rad = math.radians(centroid[1])\n"
        "    meters_per_degree = 111320 * math.cos(lat_rad)\n"
        "    distance_deg = distance_meters / meters_per_degree\n"
        "    dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(centroid, polygon_coords[0])))\n"
        "    scale = (dist + distance_deg) / dist\n"
        "    return [[c[0] * scale, c[1] * scale] for c in polygon_coords]\n"
    ),
    "transforms/area_calculator.py": (
        "import math\n"
        "def calculate_area(polygon_coords):\n"
        "    # Project to approximate metric using Earth radius\n"
        "    R = 6371000  # Earth radius in meters\n"
        "    n = len(polygon_coords)\n"
        "    projected = []\n"
        "    for lng, lat in polygon_coords:\n"
        "        x = R * math.radians(lng) * math.cos(math.radians(lat))\n"
        "        y = R * math.radians(lat)\n"
        "        projected.append((x, y))\n"
        "    area = 0.0\n"
        "    for i in range(n):\n"
        "        j = (i + 1) % n\n"
        "        area += projected[i][0] * projected[j][1]\n"
        "        area -= projected[j][0] * projected[i][1]\n"
        "    return abs(area) / 2.0\n"
    ),
    "transforms/topology_validator.py": (
        "EPSILON = 1e-10\n"
        "def check_self_intersection(polygon):\n"
        "    segments = list(zip(polygon[:-1], polygon[1:]))\n"
        "    for i, (a, b) in enumerate(segments):\n"
        "        for j, (c, d) in enumerate(segments):\n"
        "            if abs(i - j) <= 1: continue\n"
        "            if _segments_intersect(a, b, c, d):\n"
        "                return True\n"
        "    return False\n"
        "def _segments_intersect(a, b, c, d):\n"
        "    d1 = (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])\n"
        "    d2 = (b[0]-a[0])*(d[1]-a[1]) - (b[1]-a[1])*(d[0]-a[0])\n"
        "    d3 = (d[0]-c[0])*(a[1]-c[1]) - (d[1]-c[1])*(a[0]-c[0])\n"
        "    d4 = (d[0]-c[0])*(b[1]-c[1]) - (d[1]-c[1])*(b[0]-c[0])\n"
        "    if abs(d1) < EPSILON and abs(d2) < EPSILON:\n"
        "        return True\n"
        "    return (d1 * d2 < 0) and (d3 * d4 < 0)\n"
    ),
}


# ═══ 4. remediate_infrastructure_as_code ═══

INFRA_BUGGY = {
    "docker/Dockerfile": (
        "FROM python:3.11-slim\n"
        "WORKDIR /app\n"
        "COPY requirements.txt .\n"
        "RUN pip install -r requirements.txt\n"
        "COPY . .\n"
        "EXPOSE 8000\n"
        "CMD [\"gunicorn\", \"app:app\"]\n"
    ),
    "docker/docker-compose.yml": (
        "version: '3.8'\n"
        "services:\n"
        "  app:\n"
        "    build: .\n"
        "    ports:\n"
        "      - '8000:8000'\n"
        "    environment:\n"
        "      - DATABASE_URL=postgresql://app:SuperSecret123!@db:5432/mydb\n"
        "      - SECRET_KEY=my-super-secret-key-12345\n"
        "  db:\n"
        "    image: postgres:15\n"
        "    environment:\n"
        "      POSTGRES_PASSWORD: \"SuperSecret123!\"\n"
    ),
    "kubernetes/deployment.yaml": (
        "apiVersion: apps/v1\n"
        "kind: Deployment\n"
        "metadata:\n"
        "  name: myapp\n"
        "spec:\n"
        "  replicas: 3\n"
        "  template:\n"
        "    spec:\n"
        "      containers:\n"
        "        - name: myapp\n"
        "          image: myapp:latest\n"
        "          ports:\n"
        "            - containerPort: 8000\n"
    ),
    "terraform/main.tf": (
        'resource "aws_security_group" "app_sg" {\n'
        '  name = "app-sg"\n'
        '  ingress {\n'
        '    from_port   = 0\n'
        '    to_port     = 65535\n'
        '    protocol    = "tcp"\n'
        '    cidr_blocks = ["0.0.0.0/0"]\n'
        '  }\n'
        '}\n'
    ),
    "nginx/nginx.conf": (
        "server {\n"
        "    listen 80;\n"
        "    server_name example.com;\n"
        "    location / {\n"
        "        proxy_pass http://app:8000;\n"
        "    }\n"
        "}\n"
    ),
}

INFRA_PARTIAL = {
    **INFRA_BUGGY,
    # Fix 3 of 6: Dockerfile USER, remove secrets, add resource limits
    "docker/Dockerfile": (
        "FROM python:3.11-slim\n"
        "WORKDIR /app\n"
        "COPY requirements.txt .\n"
        "RUN pip install -r requirements.txt\n"
        "COPY . .\n"
        "RUN useradd -m appuser\n"
        "USER appuser\n"
        "EXPOSE 8000\n"
        "CMD [\"gunicorn\", \"app:app\"]\n"
    ),
    "docker/docker-compose.yml": (
        "version: '3.8'\n"
        "services:\n"
        "  app:\n"
        "    build: .\n"
        "    ports:\n"
        "      - '8000:8000'\n"
        "    environment:\n"
        "      - DATABASE_URL=postgresql://app:${DB_PASSWORD}@db:5432/mydb\n"
        "      - SECRET_KEY=${SECRET_KEY}\n"
        "  db:\n"
        "    image: postgres:15\n"
        "    environment:\n"
        "      POSTGRES_PASSWORD: ${DB_PASSWORD}\n"
    ),
    "kubernetes/deployment.yaml": (
        "apiVersion: apps/v1\n"
        "kind: Deployment\n"
        "metadata:\n"
        "  name: myapp\n"
        "spec:\n"
        "  replicas: 3\n"
        "  template:\n"
        "    spec:\n"
        "      containers:\n"
        "        - name: myapp\n"
        "          image: myapp:latest\n"
        "          ports:\n"
        "            - containerPort: 8000\n"
        "          resources:\n"
        "            limits:\n"
        "              memory: 512Mi\n"
        "              cpu: 500m\n"
    ),
}

INFRA_FIXED = {
    **INFRA_PARTIAL,
    "kubernetes/deployment.yaml": (
        "apiVersion: apps/v1\n"
        "kind: Deployment\n"
        "metadata:\n"
        "  name: myapp\n"
        "spec:\n"
        "  replicas: 3\n"
        "  template:\n"
        "    spec:\n"
        "      containers:\n"
        "        - name: myapp\n"
        "          image: myapp:latest\n"
        "          ports:\n"
        "            - containerPort: 8000\n"
        "          resources:\n"
        "            limits:\n"
        "              memory: 512Mi\n"
        "              cpu: 500m\n"
        "          readinessProbe:\n"
        "            httpGet:\n"
        "              path: /health\n"
        "              port: 8000\n"
        "            initialDelaySeconds: 5\n"
        "          livenessProbe:\n"
        "            httpGet:\n"
        "              path: /health\n"
        "              port: 8000\n"
        "            initialDelaySeconds: 15\n"
    ),
    "terraform/main.tf": (
        'resource "aws_security_group" "app_sg" {\n'
        '  name = "app-sg"\n'
        '  ingress {\n'
        '    from_port   = 443\n'
        '    to_port     = 443\n'
        '    protocol    = "tcp"\n'
        '    cidr_blocks = ["10.0.0.0/8"]\n'
        '  }\n'
        '  ingress {\n'
        '    from_port   = 80\n'
        '    to_port     = 80\n'
        '    protocol    = "tcp"\n'
        '    cidr_blocks = ["10.0.0.0/8"]\n'
        '  }\n'
        '}\n'
    ),
    "nginx/nginx.conf": (
        "server {\n"
        "    listen 80;\n"
        "    server_name example.com;\n"
        "    add_header X-Frame-Options DENY;\n"
        "    add_header X-Content-Type-Options nosniff;\n"
        "    add_header Content-Security-Policy \"default-src 'self'\";\n"
        "    location / {\n"
        "        proxy_pass http://app:8000;\n"
        "    }\n"
        "}\n"
    ),
}


# ═══ 5. repair_financial_reconciliation_engine ═══

RECON_BUGGY = {
    "engine/matcher.py": (
        "class TransactionMatcher:\n"
        "    def match_transactions(self, bank_entries, ledger_entries):\n"
        "        for bank_entry in bank_entries:\n"
        "            bank_amount = float(bank_entry['amount'])\n"
        "            for ledger_entry in ledger_entries:\n"
        "                ledger_amount = float(ledger_entry['amount'])\n"
        "                if bank_amount == ledger_amount:\n"
        "                    amount_score = 100\n"
    ),
    "engine/fx_handler.py": (
        "from decimal import Decimal, ROUND_HALF_UP\n"
        "from config import FX_RATES, BASE_CURRENCY, FX_SPREAD_PERCENT\n"
        "class FXHandler:\n"
        "    def __init__(self):\n"
        "        self.rates = FX_RATES\n"
        "        self.spread = FX_SPREAD_PERCENT\n"
        "    def convert_to_base(self, amount, currency, direction='buy'):\n"
        "        mid_rate = self.rates[f'{currency}_{BASE_CURRENCY}']\n"
        "        effective_rate = mid_rate\n"
        "        converted = Decimal(str(amount)) * effective_rate\n"
        "        return converted.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)\n"
    ),
    "engine/date_handler.py": (
        "from datetime import datetime\n"
        "from config import BANK_TIMEZONE, LEDGER_TIMEZONE\n"
        "def normalize_dates(bank_date_str, ledger_date_str):\n"
        "    bank_date = datetime.strptime(str(bank_date_str)[:10], '%Y-%m-%d')\n"
        "    ledger_date = datetime.strptime(str(ledger_date_str)[:10], '%Y-%m-%d')\n"
        "    return bank_date, ledger_date\n"
    ),
    "engine/tolerance_checker.py": (
        "from decimal import Decimal\n"
        "from config import AMOUNT_TOLERANCE_PERCENT\n"
        "def within_tolerance(bank_amount, ledger_amount, tolerance_pct=AMOUNT_TOLERANCE_PERCENT):\n"
        "    bank_dec = Decimal(str(bank_amount))\n"
        "    ledger_dec = Decimal(str(ledger_amount))\n"
        "    diff = abs(bank_dec - ledger_dec)\n"
        "    tolerance_amount = abs(bank_dec) * tolerance_pct\n"
        "    return diff <= tolerance_amount\n"
    ),
    "engine/exception_reporter.py": (
        "from collections import defaultdict\n"
        "class ExceptionReporter:\n"
        "    def generate_report(self, bank_exceptions, ledger_exceptions, output_path=None):\n"
        "        all_exceptions = []\n"
        "        for entry in bank_exceptions:\n"
        "            all_exceptions.append({'source': 'bank', 'amount': float(entry.get('amount', 0))})\n"
        "        grouped = defaultdict(list)\n"
        "        for exc in all_exceptions:\n"
        "            key = abs(exc['amount'])\n"
        "            grouped[key].append(exc)\n"
    ),
    "config.py": "AMOUNT_TOLERANCE_PERCENT = '0.01'\n",
    "run_reconciliation.py": "if __name__ == '__main__': pass\n",
}

RECON_PARTIAL = {
    **RECON_BUGGY,
    # Fix 2 of 5: tolerance matching + signed grouping
    "engine/matcher.py": (
        "from decimal import Decimal\n"
        "from engine.tolerance_checker import within_tolerance\n"
        "class TransactionMatcher:\n"
        "    def match_transactions(self, bank_entries, ledger_entries):\n"
        "        for bank_entry in bank_entries:\n"
        "            bank_amount = Decimal(str(bank_entry['amount']))\n"
        "            for ledger_entry in ledger_entries:\n"
        "                ledger_amount = Decimal(str(ledger_entry['amount']))\n"
        "                if within_tolerance(bank_amount, ledger_amount):\n"
        "                    amount_score = 100\n"
    ),
    "engine/exception_reporter.py": (
        "from collections import defaultdict\n"
        "class ExceptionReporter:\n"
        "    def generate_report(self, bank_exceptions, ledger_exceptions, output_path=None):\n"
        "        all_exceptions = []\n"
        "        for entry in bank_exceptions:\n"
        "            all_exceptions.append({'source': 'bank', 'amount': float(entry.get('amount', 0))})\n"
        "        grouped = defaultdict(list)\n"
        "        for exc in all_exceptions:\n"
        "            key = exc['amount']  # signed amount, not abs\n"
        "            grouped[key].append(exc)\n"
    ),
}

RECON_FIXED = {
    **RECON_PARTIAL,
    "engine/fx_handler.py": (
        "from decimal import Decimal, ROUND_HALF_UP\n"
        "from config import FX_RATES, BASE_CURRENCY, FX_SPREAD_PERCENT\n"
        "class FXHandler:\n"
        "    def __init__(self):\n"
        "        self.rates = FX_RATES\n"
        "        self.spread = FX_SPREAD_PERCENT\n"
        "    def convert_to_base(self, amount, currency, direction='buy'):\n"
        "        mid_rate = self.rates[f'{currency}_{BASE_CURRENCY}']\n"
        "        if direction == 'buy':\n"
        "            effective_rate = mid_rate * (1 + self.spread)\n"
        "        else:\n"
        "            effective_rate = mid_rate * (1 - self.spread)\n"
        "        converted = Decimal(str(amount)) * effective_rate\n"
        "        return converted.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)\n"
    ),
    "engine/date_handler.py": (
        "from datetime import datetime\n"
        "import pytz\n"
        "from config import BANK_TIMEZONE, LEDGER_TIMEZONE\n"
        "def normalize_dates(bank_date_str, ledger_date_str):\n"
        "    bank_tz = pytz.timezone(BANK_TIMEZONE)\n"
        "    ledger_tz = pytz.timezone(LEDGER_TIMEZONE)\n"
        "    bank_date = datetime.strptime(str(bank_date_str)[:10], '%Y-%m-%d')\n"
        "    bank_date = bank_tz.localize(bank_date)\n"
        "    ledger_date = datetime.strptime(str(ledger_date_str)[:10], '%Y-%m-%d')\n"
        "    ledger_date = ledger_tz.localize(ledger_date)\n"
        "    bank_date = bank_date.astimezone(pytz.UTC)\n"
        "    ledger_date = ledger_date.astimezone(pytz.UTC)\n"
        "    return bank_date, ledger_date\n"
    ),
    "engine/tolerance_checker.py": (
        "from decimal import Decimal\n"
        "from config import AMOUNT_TOLERANCE_PERCENT\n"
        "def within_tolerance(bank_amount, ledger_amount, tolerance_pct=AMOUNT_TOLERANCE_PERCENT):\n"
        "    bank_dec = Decimal(str(bank_amount))\n"
        "    ledger_dec = Decimal(str(ledger_amount))\n"
        "    diff = abs(bank_dec - ledger_dec)\n"
        "    tolerance_amount = max(abs(bank_dec), abs(ledger_dec)) * tolerance_pct\n"
        "    return diff <= tolerance_amount\n"
    ),
}


# ──────────────────────────────────────────────────────────
# Test runner
# ──────────────────────────────────────────────────────────

TASKS = [
    {
        "name": "audit_clinical_trial_pipeline",
        "verify_fn": "verify_clinical_trial_pipeline",
        "result_path": "/tmp/clinical_trial_result.json",
        "buggy": CLINICAL_BUGGY,
        "partial": CLINICAL_PARTIAL,
        "fixed": CLINICAL_FIXED,
        "num_bugs": 6,
        "points_per_bug": 17,  # approximate
    },
    {
        "name": "debug_distributed_payment_system",
        "verify_fn": "verify_payment_system",
        "result_path": "/tmp/payment_system_result.json",
        "buggy": PAYMENT_BUGGY,
        "partial": PAYMENT_PARTIAL,
        "fixed": PAYMENT_FIXED,
        "num_bugs": 5,
        "points_per_bug": 20,
    },
    {
        "name": "fix_geospatial_etl_pipeline",
        "verify_fn": "verify_geospatial_pipeline",
        "result_path": "/tmp/geospatial_pipeline_result.json",
        "buggy": GEOSPATIAL_BUGGY,
        "partial": GEOSPATIAL_PARTIAL,
        "fixed": GEOSPATIAL_FIXED,
        "num_bugs": 5,
        "points_per_bug": 20,
    },
    {
        "name": "remediate_infrastructure_as_code",
        "verify_fn": "verify_infrastructure_remediation",
        "result_path": "/tmp/infra_remediation_result.json",
        "buggy": INFRA_BUGGY,
        "partial": INFRA_PARTIAL,
        "fixed": INFRA_FIXED,
        "num_bugs": 6,
        "points_per_bug": 17,
    },
    {
        "name": "repair_financial_reconciliation_engine",
        "verify_fn": "verify_reconciliation_engine",
        "result_path": "/tmp/reconciliation_result.json",
        "buggy": RECON_BUGGY,
        "partial": RECON_PARTIAL,
        "fixed": RECON_FIXED,
        "num_bugs": 5,
        "points_per_bug": 20,
    },
]


def run_tests():
    passed = 0
    failed = 0
    errors = []

    for task in TASKS:
        name = task["name"]
        print(f"\n{'='*60}")
        print(f"TESTING: {name}")
        print(f"{'='*60}")

        try:
            mod = load_verifier(name)
            verify_fn = getattr(mod, task["verify_fn"])
            task_info = {"metadata": {}}

            # ── Test 1: File missing (export never ran) ──
            print(f"\n  [1] Do-nothing (file missing)...")
            r = verify_fn([], make_env_missing(), task_info)
            assert r["passed"] is False, f"Should fail when file missing"
            assert r["score"] == 0, f"Score should be 0, got {r['score']}"
            print(f"      PASS: passed={r['passed']}, score={r['score']}")
            passed += 1

            # ── Test 2: Do-nothing (original buggy code) ──
            print(f"\n  [2] Do-nothing (original buggy code)...")
            env = make_env(task["buggy"], task["result_path"])
            r = verify_fn([], env, task_info)
            assert r["passed"] is False, f"Buggy code should not pass! Got: {r}"
            print(f"      PASS: passed={r['passed']}, score={r['score']}")
            print(f"      Feedback: {r['feedback'][:200]}")
            passed += 1

            # ── Test 3: Partial fix ──
            print(f"\n  [3] Partial fix...")
            env = make_env(task["partial"], task["result_path"])
            r = verify_fn([], env, task_info)
            assert r["passed"] is False, f"Partial should not pass! Got: {r}"
            assert r["score"] > 0, f"Partial score should be > 0, got {r['score']}"
            assert r["score"] < 60, f"Partial score should be < 60, got {r['score']}"
            print(f"      PASS: passed={r['passed']}, score={r['score']}")
            print(f"      Feedback: {r['feedback'][:200]}")
            passed += 1

            # ── Test 4: Full fix ──
            print(f"\n  [4] Full fix...")
            env = make_env(task["fixed"], task["result_path"])
            r = verify_fn([], env, task_info)
            assert r["passed"] is True, f"Full fix should pass! Got: {r}"
            assert r["score"] >= 60, f"Full fix score should be >= 60, got {r['score']}"
            print(f"      PASS: passed={r['passed']}, score={r['score']}")
            print(f"      Feedback: {r['feedback'][:200]}")
            passed += 1

        except AssertionError as e:
            print(f"      FAIL: {e}")
            failed += 1
            errors.append((name, str(e)))
        except Exception as e:
            print(f"      ERROR: {e}")
            failed += 1
            errors.append((name, f"Exception: {e}"))

    print(f"\n{'='*60}")
    print(f"SUMMARY: {passed} passed, {failed} failed")
    if errors:
        print(f"\nFailed tests:")
        for name, err in errors:
            print(f"  - {name}: {err}")
    print(f"{'='*60}")

    return failed == 0


if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
