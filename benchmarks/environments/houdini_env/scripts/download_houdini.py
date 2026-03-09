#!/usr/bin/env python3
"""
Download Houdini from SideFX using their Web API.

Requires SideFX API credentials (client_id, client_secret).
Get them from: https://www.sidefx.com/services/

Usage:
    python3 download_houdini.py --client-id ID --client-secret SECRET [--version 20.5]
    python3 download_houdini.py --credentials-file /path/to/creds.env [--version 20.5]

The credentials file should contain:
    SIDEFX_CLIENT_ID=your_client_id
    SIDEFX_CLIENT_SECRET=your_client_secret
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.request
import urllib.parse
import urllib.error


def get_access_token(client_id, client_secret):
    """Get OAuth2 access token from SideFX."""
    url = "https://www.sidefx.com/oauth2/application_token"
    data = urllib.parse.urlencode({
        "grant_type": "client_credentials",
    }).encode("utf-8")

    request = urllib.request.Request(url, data=data)
    # Basic auth with client_id:client_secret
    import base64
    credentials = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    request.add_header("Authorization", f"Basic {credentials}")

    try:
        response = urllib.request.urlopen(request, timeout=30)
        result = json.loads(response.read().decode("utf-8"))
        return result["access_token"]
    except urllib.error.HTTPError as e:
        print(f"ERROR: Failed to get access token: {e.code} {e.reason}", file=sys.stderr)
        body = e.read().decode("utf-8", errors="replace")
        print(f"  Response: {body}", file=sys.stderr)
        sys.exit(1)


def get_build_info(access_token, product="houdini", version=None, platform="linux"):
    """Get download info for the latest build."""
    url = "https://www.sidefx.com/api/download/get-build"
    params = {
        "product": product,
        "platform": platform,
        "only_production": "true",
    }
    if version:
        params["version"] = version

    query = urllib.parse.urlencode(params)
    request = urllib.request.Request(f"{url}?{query}")
    request.add_header("Authorization", f"Bearer {access_token}")
    request.add_header("Accept", "application/json")

    try:
        response = urllib.request.urlopen(request, timeout=30)
        return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"ERROR: Failed to get build info: {e.code} {e.reason}", file=sys.stderr)
        body = e.read().decode("utf-8", errors="replace")
        print(f"  Response: {body}", file=sys.stderr)
        sys.exit(1)


def get_download_url(access_token, build_info):
    """Get the actual download URL for a build."""
    url = "https://www.sidefx.com/api/download/get-build-download"
    data = urllib.parse.urlencode({
        "build": build_info.get("build"),
        "product": build_info.get("product", "houdini"),
    }).encode("utf-8")

    request = urllib.request.Request(url, data=data)
    request.add_header("Authorization", f"Bearer {access_token}")
    request.add_header("Accept", "application/json")

    try:
        response = urllib.request.urlopen(request, timeout=30)
        return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"ERROR: Failed to get download URL: {e.code} {e.reason}", file=sys.stderr)
        body = e.read().decode("utf-8", errors="replace")
        print(f"  Response: {body}", file=sys.stderr)
        sys.exit(1)


def download_file(url, output_path, expected_hash=None):
    """Download a file with progress reporting."""
    print(f"Downloading: {url}")
    print(f"Saving to: {output_path}")

    try:
        response = urllib.request.urlopen(url, timeout=300)
        total_size = int(response.headers.get("Content-Length", 0))
        downloaded = 0
        block_size = 1024 * 1024  # 1MB
        sha256 = hashlib.sha256()

        with open(output_path, "wb") as f:
            while True:
                block = response.read(block_size)
                if not block:
                    break
                f.write(block)
                sha256.update(block)
                downloaded += len(block)
                if total_size:
                    pct = (downloaded / total_size) * 100
                    print(f"\r  Progress: {downloaded / (1024*1024):.1f}MB / {total_size / (1024*1024):.1f}MB ({pct:.1f}%)", end="", flush=True)

        print()  # newline after progress

        if expected_hash:
            actual_hash = sha256.hexdigest()
            if actual_hash != expected_hash:
                print(f"WARNING: Hash mismatch! Expected {expected_hash}, got {actual_hash}", file=sys.stderr)
            else:
                print(f"  Hash verified: {actual_hash[:16]}...")

        print(f"  Download complete: {os.path.getsize(output_path) / (1024*1024):.1f}MB")
        return True

    except Exception as e:
        print(f"ERROR: Download failed: {e}", file=sys.stderr)
        if os.path.exists(output_path):
            os.unlink(output_path)
        return False


def load_credentials(credentials_file):
    """Load credentials from an env file."""
    client_id = None
    client_secret = None

    if not os.path.exists(credentials_file):
        return None, None

    with open(credentials_file) as f:
        for line in f:
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip("'\"")
            if key == "SIDEFX_CLIENT_ID":
                client_id = value
            elif key == "SIDEFX_CLIENT_SECRET":
                client_secret = value

    return client_id, client_secret


def main():
    parser = argparse.ArgumentParser(description="Download Houdini from SideFX")
    parser.add_argument("--client-id", help="SideFX API client ID")
    parser.add_argument("--client-secret", help="SideFX API client secret")
    parser.add_argument("--credentials-file", default="/workspace/config/sidefx_credentials.env",
                        help="Path to credentials file")
    parser.add_argument("--version", default=None, help="Houdini version (e.g., 20.5)")
    parser.add_argument("--output-dir", default="/tmp/houdini_download",
                        help="Directory to save the installer")
    parser.add_argument("--platform", default="linux", help="Platform (linux, win64, macos)")
    args = parser.parse_args()

    # Get credentials
    client_id = args.client_id or os.environ.get("SIDEFX_CLIENT_ID")
    client_secret = args.client_secret or os.environ.get("SIDEFX_CLIENT_SECRET")

    if not client_id or not client_secret:
        cid, csec = load_credentials(args.credentials_file)
        client_id = client_id or cid
        client_secret = client_secret or csec

    if not client_id or not client_secret:
        print("ERROR: SideFX API credentials required.", file=sys.stderr)
        print("  Provide via --client-id/--client-secret, env vars, or credentials file.", file=sys.stderr)
        print("  Get credentials at: https://www.sidefx.com/services/", file=sys.stderr)
        sys.exit(1)

    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)

    # Step 1: Get access token
    print("Step 1: Authenticating with SideFX...")
    token = get_access_token(client_id, client_secret)
    print("  Authentication successful")

    # Step 2: Get build info
    print(f"Step 2: Finding latest Houdini build (version={args.version or 'latest'})...")
    build_info = get_build_info(token, version=args.version, platform=args.platform)
    build_version = build_info.get("version", "unknown")
    build_number = build_info.get("build", "unknown")
    print(f"  Found: Houdini {build_version}.{build_number}")

    # Step 3: Get download URL
    print("Step 3: Getting download URL...")
    download_info = get_download_url(token, build_info)
    download_url = download_info.get("download_url")
    expected_hash = download_info.get("hash")
    filename = download_info.get("filename", f"houdini-{build_version}.{build_number}-linux_x86_64.tar.gz")

    if not download_url:
        print("ERROR: No download URL returned", file=sys.stderr)
        sys.exit(1)

    # Step 4: Download
    output_path = os.path.join(args.output_dir, filename)
    print(f"Step 4: Downloading {filename}...")
    success = download_file(download_url, output_path, expected_hash)

    if success:
        print(f"\nSuccess! Installer saved to: {output_path}")
        # Write metadata
        meta_path = os.path.join(args.output_dir, "build_info.json")
        with open(meta_path, "w") as f:
            json.dump({
                "version": build_version,
                "build": build_number,
                "filename": filename,
                "path": output_path,
                "platform": args.platform,
            }, f, indent=2)
        print(f"Build info saved to: {meta_path}")
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
