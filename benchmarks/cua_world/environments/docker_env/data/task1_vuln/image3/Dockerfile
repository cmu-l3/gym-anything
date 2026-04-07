# Task 1 - Image 3: Python data processing service
# Uses ubuntu:20.04 (LTS, working repos) with
# intentionally old Python packages that have documented CRITICAL CVEs.
# Pillow==8.2.0 has CVE-2021-34552 (CRITICAL 9.8 - buffer overflow in FliDecode)
# lxml==4.8.0 has CVE-2022-2309 (HIGH - NULL pointer dereference)
# Fix: upgrade Pillow>=9.0.0 and lxml>=4.9.1 in requirements.txt, then rebuild.
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    libxml2 \
    libxslt1.1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY processor.py .

CMD ["python3", "processor.py"]
