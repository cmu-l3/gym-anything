"""
VLM (Vision Language Model) utilities for hybrid verification.

This module provides functions to query VLMs for visual verification tasks.
Supports:
- Local LLMs via OpenAI-compatible API (vLLM, etc.)
- Anthropic Claude
- OpenAI GPT models

Usage:
    from vlm_utils import query_vlm, get_final_screenshot, parse_vlm_json

Environment Variables:
    VLM_BACKEND: Which backend to use ("local", "anthropic", "openai")
    VLM_BASE_URL: Base URL for local LLM server (e.g., "http://localhost:8080/v1")
    VLM_MODEL: Model name (e.g., "Qwen/Qwen3-VL-8B-Instruct", "claude-sonnet-4-5")
    ANTHROPIC_API_KEY: Anthropic API key (for Claude)
    OPENAI_API_KEY: OpenAI API key (for GPT models)
"""

import os
import re
import json
import base64
import logging
import time
from pathlib import Path
from typing import Dict, Any, List, Optional, Union

from dotenv import load_dotenv
load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# CONFIGURATION
# =============================================================================

# Default models for each backend
DEFAULT_MODELS = {
    "local": "Qwen/Qwen3-VL-8B-Instruct",
    "anthropic": "claude-sonnet-4-5",
    "openai": "gpt-4o",
}

# Default local server URL
DEFAULT_LOCAL_URL = "http://localhost:8080/v1"


def get_vlm_config() -> Dict[str, Any]:
    """Get VLM configuration from environment variables."""
    backend = os.environ.get("VLM_BACKEND", "local").lower()

    config = {
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


# =============================================================================
# IMAGE ENCODING
# =============================================================================

def encode_image_base64(image_path: str) -> Optional[str]:
    """Encode an image file to base64 string."""
    try:
        path = Path(image_path)
        if not path.exists():
            logger.warning(f"Image not found: {image_path}")
            return None

        return base64.b64encode(path.read_bytes()).decode("utf-8")
    except Exception as e:
        logger.error(f"Error encoding image {image_path}: {e}")
        return None


def get_image_media_type(image_path: str) -> str:
    """Get the media type for an image file."""
    ext = Path(image_path).suffix.lower()
    media_types = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }
    return media_types.get(ext, "image/png")


# =============================================================================
# MESSAGE BUILDING
# =============================================================================

def build_anthropic_messages(
    prompt: str,
    images: List[Dict[str, str]],
) -> List[Dict[str, Any]]:
    """Build messages in Anthropic format."""
    content = []

    # Add images first
    for img in images:
        content.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": img["media_type"],
                "data": img["base64"],
            },
        })

    # Add text prompt
    content.append({
        "type": "text",
        "text": prompt,
    })

    return [{"role": "user", "content": content}]


def build_openai_messages(
    prompt: str,
    images: List[Dict[str, str]],
) -> List[Dict[str, Any]]:
    """Build messages in OpenAI format (also works for local vLLM servers)."""
    content = []

    # Add images first
    for img in images:
        content.append({
            "type": "image_url",
            "image_url": {
                "url": f"data:{img['media_type']};base64,{img['base64']}",
            },
        })

    # Add text prompt
    content.append({
        "type": "text",
        "text": prompt,
    })

    return [{"role": "user", "content": content}]


# =============================================================================
# VLM QUERY FUNCTIONS
# =============================================================================

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
        prompt: The text prompt to send to the VLM
        images: List of image paths to include (multiple images)
        image: Single image path (convenience for single image)
        max_tokens: Maximum tokens in response
        temperature: Sampling temperature (lower = more deterministic)
        top_p: Top-p sampling parameter

    Returns:
        Dict with:
            - success: bool
            - response: str (raw response text)
            - parsed: Dict (parsed JSON if response contains JSON)
            - error: str (if success=False)
    """
    config = get_vlm_config()

    # Handle single image convenience parameter
    image_list = images or []
    if image:
        image_list = [image] + image_list

    # Encode images
    encoded_images = []
    for img_path in image_list:
        encoded = encode_image_base64(img_path)
        if encoded:
            encoded_images.append({
                "base64": encoded,
                "media_type": get_image_media_type(img_path),
                "path": img_path,
            })

    # Call appropriate backend
    if config["backend"] == "anthropic":
        return _query_anthropic(prompt, encoded_images, config, max_tokens, temperature)
    elif config["backend"] == "openai":
        return _query_openai_api(prompt, encoded_images, config, max_tokens, temperature, top_p)
    else:  # local (default)
        return _query_local(prompt, encoded_images, config, max_tokens, temperature, top_p)


def _query_local(
    prompt: str,
    images: List[Dict],
    config: Dict[str, Any],
    max_tokens: int,
    temperature: float,
    top_p: float,
) -> Dict[str, Any]:
    """Query local LLM via OpenAI-compatible API (vLLM, etc.)."""
    try:
        from openai import OpenAI

        client = OpenAI(
            base_url=config["base_url"],
            api_key=config["api_key"],
        )

        messages = build_openai_messages(prompt, images)

        for attempt in range(config["max_retries"]):
            try:
                response = client.chat.completions.create(
                    model=config["model"],
                    messages=messages,
                    max_tokens=max_tokens,
                    temperature=temperature,
                    top_p=top_p,
                )

                response_text = response.choices[0].message.content or ""

                return {
                    "success": True,
                    "response": response_text,
                    "parsed": parse_vlm_json(response_text),
                    "error": "",
                }

            except Exception as e:
                logger.warning(f"Local LLM attempt {attempt + 1}/{config['max_retries']} failed: {e}")
                if attempt < config["max_retries"] - 1:
                    time.sleep(2 ** attempt)
                else:
                    raise

    except ImportError:
        return {
            "success": False,
            "response": "",
            "parsed": {},
            "error": "openai package not installed. Run: pip install openai",
        }
    except Exception as e:
        logger.error(f"Local LLM error: {e}")
        return {
            "success": False,
            "response": "",
            "parsed": {},
            "error": str(e),
        }


def _query_openai_api(
    prompt: str,
    images: List[Dict],
    config: Dict[str, Any],
    max_tokens: int,
    temperature: float,
    top_p: float,
) -> Dict[str, Any]:
    """Query OpenAI API (GPT-4o, GPT-5, etc.)."""
    try:
        from openai import OpenAI

        if not config.get("api_key"):
            return {
                "success": False,
                "response": "",
                "parsed": {},
                "error": "No OPENAI_API_KEY found in environment.",
            }

        client = OpenAI(api_key=config["api_key"])
        messages = build_openai_messages(prompt, images)

        for attempt in range(config["max_retries"]):
            try:
                # Check if using reasoning model (gpt-5, o1, etc.)
                model = config["model"]
                extra_kwargs = {}
                if "gpt-5" in model or model.startswith("o1") or model.startswith("o3"):
                    extra_kwargs["reasoning_effort"] = "medium"

                response = client.chat.completions.create(
                    model=model,
                    messages=messages,
                    max_tokens=max_tokens,
                    temperature=temperature if "reasoning_effort" not in extra_kwargs else None,
                    top_p=top_p if "reasoning_effort" not in extra_kwargs else None,
                    **extra_kwargs,
                )

                response_text = response.choices[0].message.content or ""

                return {
                    "success": True,
                    "response": response_text,
                    "parsed": parse_vlm_json(response_text),
                    "error": "",
                }

            except Exception as e:
                logger.warning(f"OpenAI API attempt {attempt + 1}/{config['max_retries']} failed: {e}")
                if attempt < config["max_retries"] - 1:
                    time.sleep(2 ** attempt)
                else:
                    raise

    except ImportError:
        return {
            "success": False,
            "response": "",
            "parsed": {},
            "error": "openai package not installed. Run: pip install openai",
        }
    except Exception as e:
        logger.error(f"OpenAI API error: {e}")
        return {
            "success": False,
            "response": "",
            "parsed": {},
            "error": str(e),
        }


def _query_anthropic(
    prompt: str,
    images: List[Dict],
    config: Dict[str, Any],
    max_tokens: int,
    temperature: float,
) -> Dict[str, Any]:
    """Query Anthropic Claude."""
    try:
        from anthropic import Anthropic

        if not config.get("api_key"):
            return {
                "success": False,
                "response": "",
                "parsed": {},
                "error": "No ANTHROPIC_API_KEY found in environment.",
            }

        client = Anthropic(api_key=config["api_key"])
        messages = build_anthropic_messages(prompt, images)

        for attempt in range(config["max_retries"]):
            try:
                # Check if model supports thinking (Claude 3.5+, Claude 4+)
                model = config["model"]
                extra_kwargs = {}
                if "sonnet-4" in model or "opus-4" in model or "4-5" in model:
                    extra_kwargs["thinking"] = {"type": "enabled", "budget_tokens": 2048}

                response = client.messages.create(
                    model=model,
                    max_tokens=max_tokens,
                    messages=messages,
                    temperature=temperature if "thinking" not in extra_kwargs else None,
                    **extra_kwargs,
                )

                # Handle response with thinking blocks
                response_text = ""
                for block in response.content:
                    if hasattr(block, "text"):
                        response_text = block.text
                        break

                return {
                    "success": True,
                    "response": response_text,
                    "parsed": parse_vlm_json(response_text),
                    "error": "",
                }

            except Exception as e:
                logger.warning(f"Anthropic API attempt {attempt + 1}/{config['max_retries']} failed: {e}")
                if attempt < config["max_retries"] - 1:
                    time.sleep(2 ** attempt)
                else:
                    raise

    except ImportError:
        return {
            "success": False,
            "response": "",
            "parsed": {},
            "error": "anthropic package not installed. Run: pip install anthropic",
        }
    except Exception as e:
        logger.error(f"Anthropic API error: {e}")
        return {
            "success": False,
            "response": "",
            "parsed": {},
            "error": str(e),
        }


# =============================================================================
# RESPONSE PARSING
# =============================================================================

def parse_vlm_json(response_text: str) -> Dict[str, Any]:
    """
    Parse JSON from VLM response text.

    Handles cases where JSON is embedded in other text or code blocks.
    Returns empty dict if parsing fails.
    """
    if not response_text:
        return {}

    # Try direct JSON parse first
    try:
        return json.loads(response_text)
    except json.JSONDecodeError:
        pass

    # Try to extract from code block (```json ... ```)
    try:
        if "```json" in response_text:
            json_str = response_text.split("```json")[1].split("```")[0]
            return json.loads(json_str.strip())
        elif "```" in response_text:
            json_str = response_text.split("```")[1].split("```")[0]
            return json.loads(json_str.strip())
    except (json.JSONDecodeError, IndexError):
        pass

    # Try to find JSON object in response
    try:
        match = re.search(r'\{[\s\S]*\}', response_text)
        if match:
            return json.loads(match.group())
    except json.JSONDecodeError:
        pass

    # Try to find JSON array
    try:
        match = re.search(r'\[[\s\S]*\]', response_text)
        if match:
            return {"items": json.loads(match.group())}
    except json.JSONDecodeError:
        pass

    # Fallback: try to extract boolean answers
    result = {}
    text_lower = response_text.lower()

    # Common patterns
    if "yes" in text_lower and "no" not in text_lower:
        result["answer"] = True
    elif "no" in text_lower and "yes" not in text_lower:
        result["answer"] = False
    elif "true" in text_lower:
        result["answer"] = True
    elif "false" in text_lower:
        result["answer"] = False

    # Confidence extraction
    if "high confidence" in text_lower or "confident" in text_lower:
        result["confidence"] = "high"
    elif "medium confidence" in text_lower or "moderate" in text_lower:
        result["confidence"] = "medium"
    elif "low confidence" in text_lower or "uncertain" in text_lower:
        result["confidence"] = "low"

    return result


def extract_boolean(response: Dict[str, Any], key: str, default: bool = False) -> bool:
    """Extract a boolean value from VLM response, handling various formats."""
    parsed = response.get("parsed", {})

    # Direct key lookup
    if key in parsed:
        val = parsed[key]
        if isinstance(val, bool):
            return val
        if isinstance(val, str):
            return val.lower() in ("true", "yes", "1")

    # Check raw response for the key
    response_text = response.get("response", "").lower()

    # Pattern: "key: yes/no" or "key = true/false"
    pattern = rf'{key.lower()}[:\s=]+\s*(yes|no|true|false)'
    match = re.search(pattern, response_text)
    if match:
        return match.group(1) in ("yes", "true")

    return default


# =============================================================================
# TRAJECTORY UTILITIES
# =============================================================================

def sample_trajectory_frames(
    traj: Dict[str, Any],
    num_samples: int = 5,
    include_first: bool = True,
    include_last: bool = True,
) -> List[str]:
    """
    Sample frames from a trajectory for VLM analysis.

    Args:
        traj: Trajectory dict from verification runner
        num_samples: Total number of frames to return
        include_first: Always include first frame
        include_last: Always include last frame

    Returns:
        List of frame paths
    """
    frames = traj.get("frames", [])

    if not frames:
        # Try final screenshot as fallback
        final = traj.get("final_screenshot")
        if final:
            return [final]
        return []

    if len(frames) <= num_samples:
        return frames

    # Calculate sample indices
    samples = []

    if include_first:
        samples.append(0)
    if include_last:
        samples.append(len(frames) - 1)

    # Fill in evenly spaced samples
    remaining = num_samples - len(samples)
    if remaining > 0:
        step = (len(frames) - 1) / (remaining + 1)
        for i in range(1, remaining + 1):
            idx = int(i * step)
            if idx not in samples and 0 <= idx < len(frames):
                samples.append(idx)

    # Sort and deduplicate
    samples = sorted(set(samples))

    return [frames[i] for i in samples if i < len(frames)]


def get_final_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Get the best available final screenshot from trajectory."""
    # Prefer post_verification, then final, then last frame
    for key in ["post_verification_screenshot", "final_screenshot", "last_frame"]:
        path = traj.get(key)
        if path and Path(path).exists():
            return path
    return None


def get_first_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Get the first screenshot from trajectory."""
    first = traj.get("first_frame")
    if first and Path(first).exists():
        return first

    frames = traj.get("frames", [])
    if frames and Path(frames[0]).exists():
        return frames[0]

    return None


# =============================================================================
# COMMON VLM PROMPTS
# =============================================================================

def build_landmark_verification_prompt(
    landmark_name: str,
    distinctive_features: List[str],
    false_positives: List[str],
) -> str:
    """Build a prompt for verifying a landmark is visible."""
    features_str = "\n".join(f"- {f}" for f in distinctive_features)
    negatives_str = "\n".join(f"- {f}" for f in false_positives)

    return f"""Examine this Google Earth screenshot carefully.

Task: Determine if {landmark_name} is visible in this view.

Distinctive features to look for:
{features_str}

This is NOT (common false positives):
{negatives_str}

Please analyze the image and respond in JSON format:
{{
    "landmark_visible": true/false,
    "landmark_identified": "name of what you see or null",
    "distinctive_features_found": ["list of features you can identify"],
    "zoom_appropriate": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}}
"""


def build_ui_state_verification_prompt(app_name: str) -> str:
    """Build a prompt for verifying application UI state."""
    return f"""Examine this screenshot of {app_name}.

Check the following:
1. Is {app_name} the visible/active application?
2. Is the main view/workspace visible (not covered by dialogs)?
3. Does the application appear to be in a normal, functional state?
4. Are there any error messages or loading indicators visible?

Respond in JSON format:
{{
    "app_visible": true/false,
    "main_view_visible": true/false,
    "normal_state": true/false,
    "errors_visible": true/false,
    "loading": true/false,
    "notes": "any relevant observations"
}}
"""


def build_change_detection_prompt(change_description: str) -> str:
    """Build a prompt for detecting changes between two images."""
    return f"""Compare these two images (BEFORE and AFTER).

The expected change is: {change_description}

Analyze both images and respond in JSON format:
{{
    "change_detected": true/false,
    "expected_change_made": true/false,
    "description_of_changes": "what changed between the images",
    "confidence": "low"/"medium"/"high"
}}
"""
