"""
AcmeCorp Analytics Service
Provides product analytics and reporting endpoints.
"""
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import datetime

app = FastAPI(title="AcmeCorp Analytics", version="1.0.0")


class SaleRecord(BaseModel):
    product_id: int
    quantity: int
    revenue: float
    date: str


class AnalyticsSummary(BaseModel):
    total_revenue: float
    total_orders: int
    avg_order_value: float
    top_product_id: Optional[int]
    period: str


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "analytics", "timestamp": datetime.datetime.utcnow().isoformat()}


@app.get("/")
async def root():
    return {"service": "AcmeCorp Analytics API", "version": "1.0.0"}


@app.post("/analytics/compute", response_model=AnalyticsSummary)
async def compute_analytics(records: List[SaleRecord]):
    if not records:
        raise HTTPException(status_code=400, detail="No records provided")

    total_revenue = sum(r.revenue for r in records)
    total_orders = len(records)
    avg_order_value = total_revenue / total_orders if total_orders else 0

    # Find top product by revenue
    product_revenue = {}
    for r in records:
        product_revenue[r.product_id] = product_revenue.get(r.product_id, 0) + r.revenue
    top_product_id = max(product_revenue, key=product_revenue.get) if product_revenue else None

    return AnalyticsSummary(
        total_revenue=round(total_revenue, 2),
        total_orders=total_orders,
        avg_order_value=round(avg_order_value, 2),
        top_product_id=top_product_id,
        period="custom"
    )
