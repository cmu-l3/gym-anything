from __future__ import annotations

from copy import deepcopy
from typing import Any, Dict, List


def _merge_lists_by_key(base_list: List[dict], add_list: List[dict], key: str) -> List[dict]:
    out = deepcopy(base_list)
    index = {item.get(key): i for i, item in enumerate(out) if isinstance(item, dict) and key in item}
    for item in add_list:
        if isinstance(item, dict) and key in item and item.get(key) in index:
            # merge dicts shallowly
            i = index[item[key]]
            merged = deepcopy(out[i])
            merged.update(item)
            out[i] = merged
        else:
            out.append(deepcopy(item))
    return out


def deep_merge_env_dict(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    """Deep-merge env dicts with special handling for observation/action lists.

    - Maps are merged recursively; override wins.
    - Lists under keys 'observation' and 'action' are merged by 'type'.
    - Other lists are concatenated with override appended.
    """
    result = deepcopy(base)
    for k, v in override.items():
        if k in ("observation", "action") and isinstance(v, list) and isinstance(result.get(k), list):
            result[k] = _merge_lists_by_key(result[k], v, key="type")
        elif isinstance(v, dict) and isinstance(result.get(k), dict):
            result[k] = deep_merge_env_dict(result[k], v)
        else:
            result[k] = deepcopy(v)
    return result

