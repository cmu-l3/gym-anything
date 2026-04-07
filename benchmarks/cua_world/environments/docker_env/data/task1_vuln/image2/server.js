'use strict';
/**
 * AcmeCorp Metrics Collector Service
 * Collects and exposes application metrics in Prometheus format.
 */
const express = require('express');
const client = require('prom-client');

const app = express();
const register = new client.Registry();

// Default metrics (CPU, memory, etc.)
client.collectDefaultMetrics({ register });

// Custom business metrics
const requestCounter = new client.Counter({
    name: 'acme_requests_total',
    help: 'Total number of requests processed',
    labelNames: ['service', 'status'],
    registers: [register],
});

const latencyHistogram = new client.Histogram({
    name: 'acme_request_latency_seconds',
    help: 'Request latency in seconds',
    labelNames: ['service'],
    buckets: [0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0],
    registers: [register],
});

app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'metrics-collector' });
});

app.get('/metrics', async (req, res) => {
    requestCounter.labels('metrics-collector', '200').inc();
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
});

app.get('/simulate', (req, res) => {
    const latency = Math.random() * 0.5;
    latencyHistogram.labels('test-service').observe(latency);
    requestCounter.labels('test-service', '200').inc();
    res.json({ latency_ms: (latency * 1000).toFixed(2) });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Metrics collector listening on port ${PORT}`);
});
