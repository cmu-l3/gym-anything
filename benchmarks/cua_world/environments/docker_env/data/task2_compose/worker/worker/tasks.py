"""
AcmeCorp Background Worker - Order Processing Tasks
Processes pending orders, updates inventory, and sends notifications.
"""
import os
import time
import logging
import psycopg2
import redis

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

DB_URL = os.environ.get("DATABASE_URL", "postgresql://acme:acme_secret_2024@db:5432/acme_store")
REDIS_URL = os.environ.get("REDIS_URL", "redis://cache:6379")


def get_db_conn():
    return psycopg2.connect(DB_URL)


def get_redis():
    return redis.from_url(REDIS_URL)


def process_pending_orders():
    """Process up to 10 pending orders per cycle."""
    try:
        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute(
            "SELECT id, total FROM orders WHERE status = 'pending' LIMIT 10"
        )
        orders = cur.fetchall()

        for order_id, total in orders:
            logger.info(f"Processing order {order_id} (total: ${total})")
            cur.execute(
                "UPDATE orders SET status = 'processing' WHERE id = %s",
                (order_id,)
            )
            conn.commit()
            # Simulate processing
            time.sleep(0.1)
            cur.execute(
                "UPDATE orders SET status = 'completed' WHERE id = %s",
                (order_id,)
            )
            conn.commit()

        cur.close()
        conn.close()
        return len(orders)
    except Exception as e:
        logger.error(f"DB error: {e}")
        return 0


def main():
    logger.info("AcmeCorp background worker starting...")

    # Wait for dependencies
    for attempt in range(30):
        try:
            conn = get_db_conn()
            conn.close()
            r = get_redis()
            r.ping()
            logger.info("Dependencies ready")
            break
        except Exception as e:
            logger.warning(f"Waiting for dependencies (attempt {attempt + 1}): {e}")
            time.sleep(2)

    logger.info("Worker loop started")
    while True:
        try:
            processed = process_pending_orders()
            if processed:
                logger.info(f"Processed {processed} orders")
        except Exception as e:
            logger.error(f"Worker error: {e}")
        time.sleep(5)


if __name__ == "__main__":
    main()
