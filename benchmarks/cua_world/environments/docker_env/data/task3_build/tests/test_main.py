"""Tests for AcmeCorp Analytics Service."""
import pytest
from fastapi.testclient import TestClient
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.main import app

client = TestClient(app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "healthy"
    assert data["service"] == "analytics"


def test_root():
    resp = client.get("/")
    assert resp.status_code == 200
    data = resp.json()
    assert "AcmeCorp" in data["service"]


def test_compute_analytics_empty():
    resp = client.post("/analytics/compute", json=[])
    assert resp.status_code == 400


def test_compute_analytics_single():
    records = [{"product_id": 1, "quantity": 5, "revenue": 249.95, "date": "2024-01-15"}]
    resp = client.post("/analytics/compute", json=records)
    assert resp.status_code == 200
    data = resp.json()
    assert data["total_orders"] == 1
    assert abs(data["total_revenue"] - 249.95) < 0.01
    assert data["top_product_id"] == 1


def test_compute_analytics_multiple():
    records = [
        {"product_id": 1, "quantity": 3, "revenue": 149.97, "date": "2024-01-10"},
        {"product_id": 2, "quantity": 1, "revenue": 549.99, "date": "2024-01-11"},
        {"product_id": 1, "quantity": 2, "revenue": 99.98, "date": "2024-01-12"},
    ]
    resp = client.post("/analytics/compute", json=records)
    assert resp.status_code == 200
    data = resp.json()
    assert data["total_orders"] == 3
    assert abs(data["total_revenue"] - 799.94) < 0.01
    assert data["top_product_id"] == 2  # highest single-record revenue
