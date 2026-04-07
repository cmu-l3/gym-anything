# AcmeCorp Analytics Service - Dockerfile (ORIGINAL - needs optimization)
#
# PROBLEMS to fix for the agent:
# 1. Uses full python:3.11 image instead of python:3.11-slim (adds ~700MB)
# 2. COPY . . comes BEFORE pip install, busting cache on every code change
# 3. No .dockerignore - copies test files, __pycache__, .git, venv etc.
# 4. pip install downloads packages every build (no cache mounts)
# 5. No multi-stage build - dev dependencies included in final image
# 6. RUN commands not combined, creating unnecessary layers

FROM python:3.11

WORKDIR /app

# Install system dependencies (bad: each RUN creates a layer)
RUN apt-get update
RUN apt-get install -y gcc libpq-dev
RUN rm -rf /var/lib/apt/lists/*

# BAD: Copy everything first, then install - destroys layer cache
COPY . .

# Install ALL dependencies including dev/test ones in production image
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir -r requirements-dev.txt

EXPOSE 8000
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
