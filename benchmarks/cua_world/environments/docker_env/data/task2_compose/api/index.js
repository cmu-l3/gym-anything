'use strict';
/**
 * AcmeCorp E-Commerce API Service
 * Provides RESTful endpoints for the store frontend.
 */
const express = require('express');
const { Pool } = require('pg');
const { createClient } = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = parseInt(process.env.PORT || '3000', 10);
const DB_URL = process.env.DATABASE_URL || 'postgresql://acme:acme_secret_2024@db:5432/acme_store';
const REDIS_URL = process.env.REDIS_URL || 'redis://cache:6379';

// Database pool
const pool = new Pool({ connectionString: DB_URL });

// Redis client
let redisClient = null;
(async () => {
    try {
        redisClient = createClient({ url: REDIS_URL });
        redisClient.on('error', (err) => console.error('Redis error:', err.message));
        await redisClient.connect();
        console.log('Redis connected');
    } catch (err) {
        console.error('Redis connection failed:', err.message);
    }
})();

app.get('/health', async (req, res) => {
    const checks = { api: 'ok', db: 'unknown', cache: 'unknown' };
    try {
        await pool.query('SELECT 1');
        checks.db = 'ok';
    } catch (e) {
        checks.db = 'error: ' + e.message;
    }
    try {
        if (redisClient && redisClient.isReady) {
            await redisClient.ping();
            checks.cache = 'ok';
        } else {
            checks.cache = 'not connected';
        }
    } catch (e) {
        checks.cache = 'error: ' + e.message;
    }
    const allOk = checks.db === 'ok' && checks.cache === 'ok';
    res.status(allOk ? 200 : 503).json(checks);
});

app.get('/products', async (req, res) => {
    try {
        // Try cache first
        if (redisClient && redisClient.isReady) {
            const cached = await redisClient.get('products:all');
            if (cached) {
                return res.json(JSON.parse(cached));
            }
        }
        const { rows } = await pool.query(
            'SELECT id, sku, name, price, stock_qty FROM products ORDER BY id'
        );
        const result = { products: rows, count: rows.length };
        // Cache for 60 seconds
        if (redisClient && redisClient.isReady) {
            await redisClient.setEx('products:all', 60, JSON.stringify(result));
        }
        res.json(result);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/products/:id', async (req, res) => {
    try {
        const { rows } = await pool.query(
            'SELECT * FROM products WHERE id = $1', [req.params.id]
        );
        if (rows.length === 0) return res.status(404).json({ error: 'not found' });
        res.json(rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`AcmeCorp API listening on port ${PORT}`);
});
