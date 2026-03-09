"""
VLM (Vision Language Model) utilities for verification.

This module provides a unified interface to query VLMs for visual verification
tasks within the Gym-Anything framework. Verifiers receive ``query_vlm`` via
``env_info['query_vlm']`` and can call it with a prompt and optional images.

Supported backends:
  - ``local``     – OpenAI-compatible server (vLLM, etc.)
  - ``openai``    – OpenAI API (GPT-4o, etc.)
  - ``anthropic`` – Anthropic Claude

Configuration is read from environment variables:
  VLM_BACKEND   : "local" (default), "openai", or "anthropic"
  VLM_MODEL     : Model name (defaults per backend below)
  VLM_BASE_URL  : Base URL for local server (default "http://localhost:8080/v1")
  VLM_API_KEY   : API key for local server (default "EMPTY")
  VLM_MAX_RETRIES : Max retry attempts (default 3)
  ANTHROPIC_API_KEY : Anthropic API key
  OPENAI_API_KEY    : OpenAI API key

Usage inside a verifier::

    def verify_task(traj, env_info, task_info):
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            result = query_vlm(image="/path/to/screenshot.png",
                               prompt="Is there a sphere in the scene?")
            # result = {"success": True, "response": "...", "parsed": {...}, "error": ""}
"""

from __future__ import annotations

import base64
import json
import logging
import os
import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_MODELS = {
    "local": "Qwen/Qwen3-VL-8B-Instruct",
    "anthropic": "claude-sonnet-4-5",
    "openai": "gpt-4o",
}

DEFAULT_LOCAL_URL = "http://localhost:8080/v1"


def get_vlm_config() -> Dict[str, Any]:
    """Return VLM configuration derived from environment variables."""
    backend = os.environ.get("VLM_BACKEND", "local").lower()

    config: Dict[str, Any] = {
        "backend": backend,
        "model": os.environ.get("VLM_MODEL", DEFAULT_MODELS.get(backend, DEFAULT_MODELS["local"])),
        "max_retries": int(os.environ.get("VLM_MAX_RETRIES", "3")),
    }

    if backend == "local":
        config["base_url"] = os.environ.get("VLM_BASE_URL", DEFAULT_LOCAL_URL)
        config["api_key"] = os.environ.get("VLM_API_KEY", "EMPTY")
    elif backend == "anthropic":
        config["api_key"] = os.environ.get("ANTHROPIC_API_KEY", "")
    elif backend == "openai":
        config["api_key"] = os.environ.get("OPENAI_API_KEY", "")

    return config


# ---------------------------------------------------------------------------
# Image encoding
# ---------------------------------------------------------------------------

def _encode_image_base64(image_path: str) -> Optional[str]:
    """Encode an image file to a base64 string."""
    try:
        path = Path(image_path)
        if not path.exists():
            logger.warning("Image not found: %s", image_path)
            return None
        return base64.b64encode(path.read_bytes()).decode("utf-8")
    except Exception as e:
        logger.error("Error encoding image %s: %s", image_path, e)
        return None


def _get_image_media_type(image_path: str) -> str:
    """Return MIME type for an image file based on extension."""
    ext = Path(image_path).suffix.lower()
    media_types = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }
    return media_types.get(ext, "image/png")


# ---------------------------------------------------------------------------
# Message building helpers (per-backend format)
# ---------------------------------------------------------------------------

def _build_anthropic_messages(
    prompt: str,
    images: List[Dict[str, str]],
) -> List[Dict[str, Any]]:
    content: List[Dict[str, Any]] = []
    for img in images:
        content.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": img["media_type"],
                "data": img["base64"],
            },
        })
    content.append({"type": "text", "text": prompt})
    return [{"role": "user", "content": content}]


def _build_openai_messages(
    prompt: str,
    images: List[Dict[str, str]],
) -> List[Dict[str, Any]]:
    content: List[Dict[str, Any]] = []
    for img in images:
        content.append({
            "type": "image_url",
            "image_url": {
                "url": f"data:{img['media_type']};base64,{img['base64']}",
            },
        })
    content.append({"type": "text", "text": prompt})
    return [{"role": "user", "content": content}]


# ---------------------------------------------------------------------------
# Backend query implementations
# ---------------------------------------------------------------------------

def _query_local(
    prompt: str,
    images: List[Dict[str, str]],
    config: Dict[str, Any],
    max_tokens: int,
    temperature: float,
    top_p: float,
) -> Dict[str, Any]:
    """Query a local OpenAI-compatible server (vLLM, etc.)."""
    try:
        from openai import OpenAI
    except ImportError:
        return _error_result("openai package not installed. Run: pip install openai")

    try:
        client = OpenAI(base_url=config["base_url"], api_key=config["api_key"])
        messages = _build_openai_messages(prompt, images)

        for attempt in range(config["max_retries"]):
            try:
                response = client.chat.completions.create(
                    model=config["model"],
                    messages=messages,
                    max_tokens=max_tokens,
                    temperature=temperature,
                    top_p=top_p,
                )
                text = response.choices[0].message.content or ""
                return {"success": True, "response": text, "parsed": parse_vlm_json(text), "error": ""}
            except Exception as e:
                logger.warning("Local LLM attempt %d/%d failed: %s", attempt + 1, config["max_retries"], e)
                if attempt < config["max_retries"] - 1:
                    time.sleep(2 ** attempt)
                else:
                    raise
    except Exception as e:
        logger.error("Local LLM error: %s", e)
        return _error_result(str(e))


def _query_openai_api(
    prompt: str,
    images: List[Dict[str, str]],
    config: Dict[str, Any],
    max_tokens: int,
    temperature: float,
    top_p: float,
) -> Dict[str, Any]:
    """Query the OpenAI API (GPT-4o, etc.)."""
    try:
        from openai import OpenAI
    except ImportError:
        return _error_result("openai package not installed. Run: pip install openai")

    if not config.get("api_key"):
        return _error_result("No OPENAI_API_KEY found in environment.")

    try:
        client = OpenAI(api_key=config["api_key"])
        messages = _build_openai_messages(prompt, images)

        for attempt in range(config["max_retries"]):
            try:
                response = client.chat.completions.create(
                    model=config["model"],
                    messages=messages,
                    max_tokens=max_tokens,
                    temperature=temperature,
                    top_p=top_p,
                )
                text = response.choices[0].message.content or ""
                return {"success": True, "response": text, "parsed": parse_vlm_json(text), "error": ""}
            except Exception as e:
                logger.warning("OpenAI API attempt %d/%d failed: %s", attempt + 1, config["max_retries"], e)
                if attempt < config["max_retries"] - 1:
                    time.sleep(2 ** attempt)
                else:
                    raise
    except Exception as e:
        logger.error("OpenAI API error: %s", e)
        return _error_result(str(e))


def _query_anthropic(
    prompt: str,
    images: List[Dict[str, str]],
    config: Dict[str, Any],
    max_tokens: int,
    temperature: float,
) -> Dict[str, Any]:
    """Query Anthropic Claude (no computer-use flags)."""
    try:
        from anthropic import Anthropic
    except ImportError:
        return _error_result("anthropic package not installed. Run: pip install anthropic")

    if not config.get("api_key"):
        return _error_result("No ANTHROPIC_API_KEY found in environment.")

    try:
        client = Anthropic(api_key=config["api_key"])
        messages = _build_anthropic_messages(prompt, images)

        for attempt in range(config["max_retries"]):
            try:
                response = client.messages.create(
                    model=config["model"],
                    max_tokens=max_tokens,
                    messages=messages,
                    temperature=temperature,
                )
                # Extract text from content blocks
                response_text = ""
                for block in response.content:
                    if hasattr(block, "text"):
                        response_text = block.text
                        break
                return {"success": True, "response": response_text, "parsed": parse_vlm_json(response_text), "error": ""}
            except Exception as e:
                logger.warning("Anthropic API attempt %d/%d failed: %s", attempt + 1, config["max_retries"], e)
                if attempt < config["max_retries"] - 1:
                    time.sleep(2 ** attempt)
                else:
                    raise
    except Exception as e:
        logger.error("Anthropic API error: %s", e)
        return _error_result(str(e))


def _error_result(msg: str) -> Dict[str, Any]:
    return {"success": False, "response": "", "parsed": {}, "error": msg}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def query_vlm(
    prompt: str,
    images: Optional[List[str]] = None,
    image: Optional[str] = None,
    max_tokens: int = 2048,
    temperature: float = 0.1,
    top_p: float = 0.95,
) -> Dict[str, Any]:
    """
    Query a VLM with a prompt and optional images.

    Args:
        prompt: Text prompt to send to the VLM.
        images: List of image file paths (for multi-image queries).
        image: Single image file path (convenience parameter).
        max_tokens: Maximum tokens in the response.
        temperature: Sampling temperature (lower = more deterministic).
        top_p: Top-p sampling parameter.

    Returns:
        Dict with keys:
            success (bool): Whether the query succeeded.
            response (str): Raw response text.
            parsed (dict): Parsed JSON extracted from response (or {}).
            error (str): Error message if success is False.
    """
    config = get_vlm_config()

    # Merge image lists
    image_list = list(images or [])
    if image:
        image_list = [image] + image_list

    # Encode images
    encoded_images: List[Dict[str, str]] = []
    for img_path in image_list:
        encoded = _encode_image_base64(img_path)
        if encoded:
            encoded_images.append({
                "base64": encoded,
                "media_type": _get_image_media_type(img_path),
            })

    # Dispatch to the configured backend
    backend = config["backend"]
    if backend == "anthropic":
        return _query_anthropic(prompt, encoded_images, config, max_tokens, temperature)
    elif backend == "openai":
        return _query_openai_api(prompt, encoded_images, config, max_tokens, temperature, top_p)
    else:  # "local" (default)
        return _query_local(prompt, encoded_images, config, max_tokens, temperature, top_p)


# ---------------------------------------------------------------------------
# Response parsing
# ---------------------------------------------------------------------------

def parse_vlm_json(response_text: str) -> Dict[str, Any]:
    """
    Parse JSON from VLM response text.

    Tries, in order: direct parse, code-block extraction, regex object/array
    match, and boolean keyword fallback.  Returns ``{}`` on failure.
    """
    if not response_text:
        return {}

    # 1. Direct JSON parse
    try:
        return json.loads(response_text)
    except json.JSONDecodeError:
        pass

    # 2. Extract from ```json ... ``` code blocks
    try:
        if "```json" in response_text:
            json_str = response_text.split("```json")[1].split("```")[0]
            return json.loads(json_str.strip())
        elif "```" in response_text:
            json_str = response_text.split("```")[1].split("```")[0]
            return json.loads(json_str.strip())
    except (json.JSONDecodeError, IndexError):
        pass

    # 3. Regex for JSON object
    try:
        match = re.search(r'\{[\s\S]*\}', response_text)
        if match:
            return json.loads(match.group())
    except json.JSONDecodeError:
        pass

    # 4. Regex for JSON array
    try:
        match = re.search(r'\[[\s\S]*\]', response_text)
        if match:
            return {"items": json.loads(match.group())}
    except json.JSONDecodeError:
        pass

    # 5. Boolean keyword fallback
    result: Dict[str, Any] = {}
    text_lower = response_text.lower()

    if "yes" in text_lower and "no" not in text_lower:
        result["answer"] = True
    elif "no" in text_lower and "yes" not in text_lower:
        result["answer"] = False
    elif "true" in text_lower:
        result["answer"] = True
    elif "false" in text_lower:
        result["answer"] = False

    if "high confidence" in text_lower or "confident" in text_lower:
        result["confidence"] = "high"
    elif "medium confidence" in text_lower or "moderate" in text_lower:
        result["confidence"] = "medium"
    elif "low confidence" in text_lower or "uncertain" in text_lower:
        result["confidence"] = "low"

    return result


def extract_boolean(response: Dict[str, Any], key: str, default: bool = False) -> bool:
    """Extract a boolean value from a VLM response dict, handling various formats."""
    parsed = response.get("parsed", {})

    if key in parsed:
        val = parsed[key]
        if isinstance(val, bool):
            return val
        if isinstance(val, str):
            return val.lower() in ("true", "yes", "1")

    response_text = response.get("response", "").lower()
    pattern = rf'{key.lower()}[:\s=]+\s*(yes|no|true|false)'
    match = re.search(pattern, response_text)
    if match:
        return match.group(1) in ("yes", "true")

    return default


# ---------------------------------------------------------------------------
# Trajectory frame helpers
# ---------------------------------------------------------------------------

def sample_trajectory_frames(
    traj: Dict[str, Any],
    num_samples: int = 3,
    include_first: bool = True,
    include_last: bool = True,
) -> List[str]:
    """
    Sample *num_samples* frame paths from a trajectory dict.

    Useful for limiting VLM cost while still covering the episode.
    """
    frames = traj.get("frames", [])

    if not frames:
        final = traj.get("final_screenshot")
        return [final] if final else []

    if len(frames) <= num_samples:
        return list(frames)

    samples: List[int] = []
    if include_first:
        samples.append(0)
    if include_last:
        samples.append(len(frames) - 1)

    remaining = num_samples - len(samples)
    if remaining > 0:
        step = (len(frames) - 1) / (remaining + 1)
        for i in range(1, remaining + 1):
            idx = int(i * step)
            if idx not in samples and 0 <= idx < len(frames):
                samples.append(idx)

    samples = sorted(set(samples))
    return [frames[i] for i in samples if i < len(frames)]


def get_final_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Return the best available final screenshot path from a trajectory."""
    for key in ("post_verification_screenshot", "final_screenshot", "last_frame"):
        path = traj.get(key)
        if path and Path(path).exists():
            return path
    return None


def get_first_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Return the first screenshot path from a trajectory."""
    first = traj.get("first_frame")
    if first and Path(first).exists():
        return first
    frames = traj.get("frames", [])
    if frames and Path(frames[0]).exists():
        return frames[0]
    return None
