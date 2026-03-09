from __future__ import annotations

from typing import Any, Dict, Optional

from gym_anything.vlm import (
    get_final_screenshot as _get_final_screenshot,
    query_vlm as _query_vlm,
    sample_trajectory_frames as _sample_trajectory_frames,
)


def query_vlm(
    prompt: str,
    image: Optional[str] = None,
    images: Optional[list[str]] = None,
    max_tokens: int = 2048,
    temperature: float = 0.1,
    top_p: float = 0.95,
) -> Dict[str, Any]:
    return _query_vlm(
        prompt=prompt,
        image=image,
        images=images,
        max_tokens=max_tokens,
        temperature=temperature,
        top_p=top_p,
    )


def sample_trajectory_frames(traj: Dict[str, Any], n: int = 3, **kwargs: Any) -> list[str]:
    num_samples = int(kwargs.pop("num_samples", n))
    include_first = bool(kwargs.pop("include_first", True))
    include_last = bool(kwargs.pop("include_last", True))
    return _sample_trajectory_frames(
        traj,
        num_samples=num_samples,
        include_first=include_first,
        include_last=include_last,
    )


def get_final_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    return _get_final_screenshot(traj)


__all__ = ["get_final_screenshot", "query_vlm", "sample_trajectory_frames"]
