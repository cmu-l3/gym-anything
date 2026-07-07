from __future__ import annotations

import base64
import os
import re
import uuid
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO

from PIL import Image

from agents.shared.llm_clients import smart_resize


def _coerce_bool(value, default=False):
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
    raise ValueError(f"expected boolean value, got {value!r}")


def _write_bytes(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def _sanitize_uuid_prefix(value):
    prefix = re.sub(r"[^A-Za-z0-9_.:-]+", "-", str(value).strip()).strip("-")
    return prefix or None


class ImagePipelineMixin:
    image_resize_factor = 32
    image_max_pixels = 16 * 16 * 4 * 1280

    def _init_image_pipeline(self):
        image_format = str(
            self.agent_args.get(
                "image_format",
                os.environ.get("GYM_ANYTHING_AGENT_IMAGE_FORMAT", "jpeg"),
            )
        ).strip().lower()
        if image_format in {"jpeg", "jpg"}:
            self.image_format = "jpeg"
            self.image_extension = "jpg"
            self.image_mime_type = "image/jpeg"
        elif image_format == "png":
            self.image_format = "png"
            self.image_extension = "png"
            self.image_mime_type = "image/png"
        elif image_format in {"prime_rgb", "prime-rgb", "raw_rgb", "raw-rgb"}:
            self.image_format = "prime_rgb"
            self.image_extension = "jpg"
            self.image_mime_type = "application/x.prime-rgb"
        else:
            raise ValueError("image_format must be 'jpeg', 'png', or 'prime_rgb'")

        self.jpeg_quality = int(
            self.agent_args.get(
                "jpeg_quality",
                os.environ.get("GYM_ANYTHING_AGENT_JPEG_QUALITY", 85),
            )
        )
        if not 1 <= self.jpeg_quality <= 100:
            raise ValueError("jpeg_quality must be between 1 and 100")

        self.async_image_save = _coerce_bool(
            self.agent_args.get(
                "async_image_save",
                os.environ.get("GYM_ANYTHING_AGENT_ASYNC_IMAGE_SAVE", "1"),
            ),
            default=True,
        )
        self.image_cache_uuids = _coerce_bool(
            self.agent_args.get(
                "image_cache_uuids",
                os.environ.get("GYM_ANYTHING_AGENT_IMAGE_CACHE_UUIDS", "0"),
            ),
            default=False,
        )
        self._image_save_executor = (
            ThreadPoolExecutor(max_workers=1, thread_name_prefix="agent-image-save")
            if self.async_image_save
            else None
        )
        self._image_save_futures = []
        self.b64_to_uuid = {}
        self.uuid_to_path = {}
        self.screenshot_uuids = []
        self._last_processed_image_uuid = None
        self._image_frame_counter = 0
        configured_uuid_prefix = self.agent_args.get(
            "image_cache_uuid_prefix",
            os.environ.get("GYM_ANYTHING_AGENT_IMAGE_CACHE_UUID_PREFIX"),
        )
        self.image_cache_uuid_prefix = _sanitize_uuid_prefix(
            configured_uuid_prefix or f"gaimg-{uuid.uuid4().hex}"
        )
        self.prime_rgb_width = int(
            self.agent_args.get(
                "prime_rgb_width",
                os.environ.get("GYM_ANYTHING_AGENT_PRIME_RGB_WIDTH", 960),
            )
        )
        self.prime_rgb_height = int(
            self.agent_args.get(
                "prime_rgb_height",
                os.environ.get("GYM_ANYTHING_AGENT_PRIME_RGB_HEIGHT", 540),
            )
        )
        self.b64_to_data_url_prefix = {}

    def _image_data_url(self, image_b64):
        prefix = self.b64_to_data_url_prefix.get(image_b64)
        if prefix:
            return f"{prefix},{image_b64}"
        return f"data:{self.image_mime_type};base64,{image_b64}"

    def _next_image_uuid(self):
        image_uuid = f"{self.image_cache_uuid_prefix}-frame-{self._image_frame_counter:06d}"
        self._image_frame_counter += 1
        return image_uuid

    def _image_content(self, image_b64, *, include_bytes, image_uuid=None):
        if not self.image_cache_uuids:
            return {
                "type": "image_url",
                "image_url": {"url": self._image_data_url(image_b64)},
            }

        image_uuid = image_uuid or self.b64_to_uuid.get(image_b64)
        if image_uuid is None:
            raise KeyError("image cache UUID missing for screenshot payload")

        return {
            "type": "image_url",
            "uuid": image_uuid,
            "image_url": {"url": self._image_data_url(image_b64)} if include_bytes else None,
        }

    def _remember_screenshot(self, image_b64):
        self.screenshots.append(image_b64)
        self.screenshot_uuids.append(self._last_processed_image_uuid or self.b64_to_uuid.get(image_b64))

    def _load_image(self, image_source):
        if isinstance(image_source, dict):
            if "image" in image_source:
                return image_source["image"].copy()
            if "path" in image_source:
                with Image.open(image_source["path"]) as source_image:
                    return source_image.copy()
            raise KeyError("screen observation must include 'image' or 'path'")

        with Image.open(image_source) as source_image:
            return source_image.copy()

    def _encode_image_bytes(self, image):
        buffer = BytesIO()
        if self.image_format == "jpeg":
            if image.mode != "RGB":
                image = image.convert("RGB")
            image.save(
                buffer,
                format="JPEG",
                quality=self.jpeg_quality,
                optimize=False,
                progressive=False,
            )
        elif self.image_format == "png":
            image.save(buffer, format="PNG")
        else:
            raise ValueError(f"unsupported encoded image format: {self.image_format}")
        return buffer.getvalue()

    def _encode_artifact_jpeg_bytes(self, image):
        buffer = BytesIO()
        if image.mode != "RGB":
            image = image.convert("RGB")
        image.save(
            buffer,
            format="JPEG",
            quality=self.jpeg_quality,
            optimize=False,
            progressive=False,
        )
        return buffer.getvalue()

    def _save_image_artifact(self, path, data):
        if self._image_save_executor is None:
            _write_bytes(path, data)
            return
        future = self._image_save_executor.submit(_write_bytes, path, data)
        self._image_save_futures.append(future)

    def _wait_for_image_saves(self):
        futures = self._image_save_futures
        self._image_save_futures = []
        for future in futures:
            future.result()
        if self._image_save_executor is not None:
            self._image_save_executor.shutdown(wait=True)
            self._image_save_executor = None

    def process_image(self, image_source):
        """
        Process an image for VLM calls.
        Returns tuple of (base64_string, processed_image_path).
        """
        image = self._load_image(image_source)
        width, height = image.size

        if self.verbose:
            print(f"Original screen resolution: {width}x{height}")

        if self.image_format == "prime_rgb":
            resized_width, resized_height = self.prime_rgb_width, self.prime_rgb_height
        else:
            resized_height, resized_width = smart_resize(
                height=height,
                width=width,
                factor=self.image_resize_factor,
                max_pixels=self.image_max_pixels,
            )
        if self.verbose:
            print("Resized image resolution: ", resized_width, resized_height)
        if image.size != (resized_width, resized_height):
            image = image.resize((resized_width, resized_height))

        if self.verbose:
            print(f"Processed image resolution: {resized_width}x{resized_height}")

        processed_path = (
            f"{self.save_folder_custom}/observation_{self.step_idx}.{self.image_extension}"
        )
        if self.image_format == "prime_rgb":
            if image.mode != "RGB":
                image = image.convert("RGB")
            processed_bytes = image.tobytes()
            artifact_bytes = self._encode_artifact_jpeg_bytes(image)
        else:
            processed_bytes = self._encode_image_bytes(image)
            artifact_bytes = processed_bytes
        self._save_image_artifact(processed_path, artifact_bytes)

        image_b64 = base64.b64encode(processed_bytes).decode("utf-8")
        if self.image_format == "prime_rgb":
            self.b64_to_data_url_prefix[image_b64] = (
                f"data:{self.image_mime_type};w={resized_width};h={resized_height};base64"
            )
        image_uuid = self._next_image_uuid()
        self.b64_to_uuid[image_b64] = image_uuid
        self.uuid_to_path[image_uuid] = processed_path
        self._last_processed_image_uuid = image_uuid

        return image_b64, processed_path
