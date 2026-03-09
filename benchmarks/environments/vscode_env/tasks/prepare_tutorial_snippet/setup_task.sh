#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prepare Tutorial Snippet Task ==="

# Create workspace structure
WORKSPACE_DIR="/home/ga/workspace"
PRODUCTION_DIR="$WORKSPACE_DIR/production"
TUTORIAL_DIR="$WORKSPACE_DIR/tutorial"

sudo -u ga mkdir -p "$PRODUCTION_DIR"
sudo -u ga mkdir -p "$TUTORIAL_DIR"

# Create production rate limiter with realistic complexity
cat > "$PRODUCTION_DIR/rate_limiter.py" << 'EOF'
"""
Production-grade token bucket rate limiter
"""
import time
import logging
from typing import Optional
from redis import Redis
from config import Config
from metrics import MetricsCollector

logger = logging.getLogger(__name__)

class TokenBucketRateLimiter:
    """Rate limiter using token bucket algorithm"""
    
    def __init__(self, cfg: Config, redis_client: Redis, metrics: MetricsCollector):
        self.cfg = cfg
        self.redis = redis_client
        self.metrics = metrics
        self.max_tkn = cfg.get('rate_limit.max_tokens', 100)
        self.refill_rt = cfg.get('rate_limit.refill_rate', 10)
        logger.info(f"Initialized rate limiter: max={self.max_tkn}, rate={self.refill_rt}")
    
    def _get_state(self, user_id: str) -> tuple:
        """Retrieve current state from Redis"""
        try:
            key = f"ratelimit:{user_id}"
            data = self.redis.hgetall(key)
            if not data:
                return self.max_tkn, time.time()
            return float(data.get(b'tokens', self.max_tkn)), float(data.get(b'last_refill', time.time()))
        except Exception as e:
            logger.error(f"Redis error: {e}")
            self.metrics.increment('redis.errors')
            return self.max_tkn, time.time()
    
    def _save_state(self, user_id: str, tkns: float, last_t: float):
        """Persist state to Redis"""
        try:
            key = f"ratelimit:{user_id}"
            self.redis.hset(key, mapping={
                'tokens': str(tkns),
                'last_refill': str(last_t)
            })
            self.redis.expire(key, 3600)
        except Exception as e:
            logger.error(f"Redis save error: {e}")
            self.metrics.increment('redis.save_errors')
    
    def allow_request(self, user_id: str, cost: int = 1) -> bool:
        """Check if request should be allowed"""
        try:
            curr_tkns, last_t = self._get_state(user_id)
            now = time.time()
            elapsed = now - last_t
            
            # Refill tokens based on elapsed time
            new_tkns = min(self.max_tkn, curr_tkns + elapsed * self.refill_rt)
            
            if new_tkns >= cost:
                new_tkns -= cost
                self._save_state(user_id, new_tkns, now)
                self.metrics.increment('requests.allowed')
                logger.debug(f"Allowed request for {user_id}, {new_tkns} tokens remaining")
                return True
            else:
                self.metrics.increment('requests.rejected')
                logger.warning(f"Rejected request for {user_id}, insufficient tokens")
                return False
        except Exception as e:
            logger.error(f"Rate limit check failed: {e}")
            self.metrics.increment('rate_limit.errors')
            return True  # Fail open for availability
EOF

# Create README with task instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Rate Limiter Tutorial Task

## Goal
Create a simplified educational version of the production rate limiter for a blog post.

## Instructions
1. Read `/home/ga/workspace/production/rate_limiter.py`
2. Create `/home/ga/workspace/tutorial/simple_rate_limiter.py`
3. Extract ONLY the core token bucket logic
4. Simplify variable names (e.g., tokens_available, last_refill_time)
5. Add explanatory comments
6. Remove: Redis, logging, error handling, configuration, metrics
7. Keep it under 50 lines and syntactically valid

## Core Algorithm to Extract
The token bucket algorithm has two main parts:
1. **Refill tokens**: Based on time elapsed, add tokens back (with a max cap)
2. **Consume tokens**: When request comes, check if enough tokens available

## Example of What to Remove
- Redis imports and operations
- Logging statements (logger.info, logger.error, etc.)
- Error handling (try/except blocks)
- Configuration objects (Config, MetricsCollector)
- Abbreviated variable names (tkn, rt, last_t)

## What to Keep/Add
- Core token refill calculation: `tokens + elapsed_time * refill_rate`
- Token consumption logic: checking and subtracting tokens
- Descriptive names: `tokens_available`, `last_refill_time`, `refill_rate`
- Explanatory comments explaining each section
- Only stdlib imports (time, typing)

The tutorial version should help readers understand the token bucket concept quickly.
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the production file
sleep 1
su - ga -c "DISPLAY=:1 code '$PRODUCTION_DIR/rate_limiter.py'" &

sleep 2

echo "=== Prepare Tutorial Snippet Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read the production rate limiter code"
echo "  2. Create /home/ga/workspace/tutorial/simple_rate_limiter.py"
echo "  3. Extract and simplify the core token bucket logic"
echo "  4. Remove Redis, logging, error handling, config, metrics"
echo "  5. Use descriptive variable names"
echo "  6. Add explanatory comments (at least 3)"
echo "  7. Keep under 50 lines"
echo "  8. Save the file (Ctrl+S)"