# Task 1 - Image 1: Python inventory API service
# Uses python:3.9-slim-bullseye (working Debian Bullseye repos) with
# intentionally old Python packages that have documented CRITICAL CVEs.
# PyYAML==5.3.1 has CVE-2020-14343 (CRITICAL 9.8 - arbitrary code execution via yaml.load())
# Fix: upgrade to PyYAML>=6.0.1 in requirements.txt, then rebuild.
FROM python:3.9-slim-bullseye

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000
CMD ["python", "app.py"]
