#!/usr/bin/env python3
"""
Cost Monitor for Model Usage Dumps

Iterates over all usage dump files in model_usage_dumps/, groups by model,
computes token usage, and calculates costs based on per-model pricing.

Usage:
    python cost_monitor.py [--usage_dir model_usage_dumps]
"""

import os
import sys
import argparse
import pickle
from glob import glob
from collections import defaultdict
from typing import Dict, Any, Optional
from tqdm import tqdm

# Pricing per million tokens (as of 2024)
# Format: {model_pattern: {prompt, completion, cache_creation, cache_read}}
MODEL_PRICING = {
    # Claude models (Anthropic pricing)
    'claude-opus-4-5': {
        'prompt': 5.0,
        'completion': 25.0,
        'cache_creation': 18.75,
        'cache_read': 0.5,
    },
    'claude-sonnet-4-5': {
        'prompt': 3.0,
        'completion': 15.0,
        'cache_creation': 3.75,
        'cache_read': 0.3,
    },
    # Databricks-hosted Claude (same pricing assumed)
    'databricks-claude-opus-4-5': {
        'prompt': 5.0,
        'completion': 25.0,
        'cache_creation': 6.25,
        'cache_read': 0.5,
    },
    'databricks-claude-sonnet-4-5': {
        'prompt': 3.0,
        'completion': 15.0,
        'cache_creation': 3.75,
        'cache_read': 0.3,
    },
    'gemini-3-flash-preview': {
        'prompt': 0.5,
        'completion': 2.0,
        'cache_creation': 0.5,
        'cache_read': 0.05,
    },
    'gemini-3-pro-preview': {
        'prompt': 2.0,
        'completion': 8.0,
        'cache_creation': 2.0,
        'cache_read': 0.02,
    },
    'gpt-5-nano': {
        'prompt': 0.05,
        'completion': 0.4,
        'cache_creation': 0.05,
        'cache_read': 0.005,
    },
    'default': {
        'prompt': 3.0,
        'completion': 15.0,
        'cache_creation': 3.75,
        'cache_read': 0.3,
    },
    'Kimi-K2.5': {
        'prompt': 0.6,
        'completion': 2.5,
        'cache_creation': 0.6,
        'cache_read': 0.6,
    },
    'Qwen_Qwen3-VL-4B-Thinking': {
        'prompt': 0.0,
        'completion': 0.0,
        'cache_creation': 0.0,
        'cache_read': 0.0,
    },
}


def get_pricing_for_model(model_name: str) -> Dict[str, float]:
    """Get pricing for a model, matching by prefix."""
    model_lower = model_name.lower()

    # Try to match model patterns
    for pattern, pricing in MODEL_PRICING.items():
        if pattern.lower() in model_lower:
            return pricing

    # Fallback to default
    print(f"No pricing found for model: {model_name}")
    return MODEL_PRICING['default']


def extract_model_from_filename(filename: str) -> str:
    """Extract model name from filename format: uuid_modelname.pkl"""
    basename = os.path.basename(filename)
    # Remove .pkl extension
    name = basename.rsplit('.', 1)[0]
    # Split by first underscore (uuid_modelname)
    parts = name.split('_', 1)
    if len(parts) >= 2:
        return parts[1]
    return 'unknown'


def extract_usage_from_response(usage_obj: Any, verbose: bool = False) -> Dict[str, int]:
    """Extract token counts from various usage object formats."""
    result = {
        'input_tokens': 0,
        'output_tokens': 0,
        'cache_creation_input_tokens': 0,
        'cache_read_input_tokens': 0,
    }

    # Handle nested usage (response.usage)
    if hasattr(usage_obj, 'usage'):
        usage_obj = usage_obj.usage

    # Handle dict format
    if isinstance(usage_obj, dict):
        result['input_tokens'] = usage_obj.get('input_tokens', 0) or usage_obj.get('prompt_tokens', 0)
        result['output_tokens'] = usage_obj.get('output_tokens', 0) or usage_obj.get('completion_tokens', 0)
        result['cache_creation_input_tokens'] = usage_obj.get('cache_creation_input_tokens', 0)
        result['cache_read_input_tokens'] = usage_obj.get('cache_read_input_tokens', 0)
    # Handle object format
    elif hasattr(usage_obj, 'input_tokens'):
        result['input_tokens'] = getattr(usage_obj, 'input_tokens', 0) or 0
        result['output_tokens'] = getattr(usage_obj, 'output_tokens', 0) or 0
        result['cache_creation_input_tokens'] = getattr(usage_obj, 'cache_creation_input_tokens', 0) or 0
        result['cache_read_input_tokens'] = getattr(usage_obj, 'cache_read_input_tokens', 0) or 0
    # OpenAI format
    elif hasattr(usage_obj, 'prompt_tokens'):
        result['input_tokens'] = getattr(usage_obj, 'prompt_tokens', 0) or 0
        result['output_tokens'] = getattr(usage_obj, 'completion_tokens', 0) or 0
        result['cache_creation_input_tokens'] = getattr(usage_obj, 'cache_creation_input_tokens', 0) or 0
        result['cache_read_input_tokens'] = getattr(usage_obj, 'cache_read_input_tokens', 0) or 0

    if verbose:
        print('WARNING: We are not sure, if both cache creation and cache read are counted as input tokens in the usage object.')
    result['input_tokens'] = result['input_tokens'] - result['cache_creation_input_tokens'] - result['cache_read_input_tokens']
    return result


def format_number(n: float) -> str:
    """Format number with commas for readability."""
    if n >= 1_000_000:
        return f"{n/1_000_000:.2f}M"
    elif n >= 1_000:
        return f"{n/1_000:.2f}K"
    else:
        return f"{n:.2f}"


def format_cost(cost: float) -> str:
    """Format cost in dollars."""
    if cost >= 1.0:
        return f"${cost:.2f}"
    elif cost >= 0.01:
        return f"${cost:.3f}"
    else:
        return f"${cost:.4f}"


def main():
    parser = argparse.ArgumentParser(description='Monitor model usage costs')
    parser.add_argument('--usage_dir', type=str, default='model_usage_dumps',
                        help='Directory containing usage dump files')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Show detailed breakdown')
    args = parser.parse_args()

    usage_dir = args.usage_dir
    if not os.path.exists(usage_dir):
        print(f"Error: Usage directory not found: {usage_dir}")
        sys.exit(1)

    # Find all pickle files
    files = glob(os.path.join(usage_dir, '*.pkl'))
    if not files:
        print(f"No usage files found in {usage_dir}/")
        sys.exit(0)

    print(f"Found {len(files)} usage files in {usage_dir}/")
    print("=" * 80)

    # Group by model
    model_stats: Dict[str, Dict[str, int]] = defaultdict(lambda: {
        'count': 0,
        'input_tokens': 0,
        'output_tokens': 0,
        'cache_creation_input_tokens': 0,
        'cache_read_input_tokens': 0,
    })

    errors = 0
    for filepath in tqdm(files, desc="Processing"):
        try:
            model_name = extract_model_from_filename(filepath)

            with open(filepath, 'rb') as f:
                usage_obj = pickle.load(f)

            usage = extract_usage_from_response(usage_obj, verbose=args.verbose)

            stats = model_stats[model_name]
            stats['count'] += 1
            stats['input_tokens'] += usage['input_tokens']
            stats['output_tokens'] += usage['output_tokens']
            stats['cache_creation_input_tokens'] += usage['cache_creation_input_tokens']
            stats['cache_read_input_tokens'] += usage['cache_read_input_tokens']

        except Exception as e:
            errors += 1
            if args.verbose:
                tqdm.write(f"Error processing {filepath}: {e}")

    if errors > 0:
        print(f"\nWarning: {errors} files could not be processed")

    # Calculate and display costs per model
    print("\n" + "=" * 80)
    print("USAGE AND COST SUMMARY BY MODEL")
    print("=" * 80)

    total_cost = 0.0
    total_input = 0
    total_output = 0
    total_cache_create = 0
    total_cache_read = 0
    total_requests = 0

    for model_name in sorted(model_stats.keys()):
        stats = model_stats[model_name]
        pricing = get_pricing_for_model(model_name)

        # Calculate costs (pricing is per million tokens)
        input_cost = pricing['prompt'] * stats['input_tokens'] / 1_000_000
        output_cost = pricing['completion'] * stats['output_tokens'] / 1_000_000
        cache_create_cost = pricing['cache_creation'] * stats['cache_creation_input_tokens'] / 1_000_000
        cache_read_cost = pricing['cache_read'] * stats['cache_read_input_tokens'] / 1_000_000
        # breakpoint()
        model_cost = input_cost + output_cost + cache_create_cost + cache_read_cost

        total_cost += model_cost
        total_input += stats['input_tokens']
        total_output += stats['output_tokens']
        total_cache_create += stats['cache_creation_input_tokens']
        total_cache_read += stats['cache_read_input_tokens']
        total_requests += stats['count']

        print(f"\n{model_name}")
        print("-" * 60)
        print(f"  Requests:       {stats['count']:,}")
        print(f"  Input tokens:   {stats['input_tokens']:,} ({format_number(stats['input_tokens'])})")
        print(f"  Output tokens:  {stats['output_tokens']:,} ({format_number(stats['output_tokens'])})")
        if stats['cache_creation_input_tokens'] > 0:
            print(f"  Cache created:  {stats['cache_creation_input_tokens']:,}")
        if stats['cache_read_input_tokens'] > 0:
            print(f"  Cache read:     {stats['cache_read_input_tokens']:,}")
        print(f"  ---")
        print(f"  Input cost:     {format_cost(input_cost)}")
        print(f"  Output cost:    {format_cost(output_cost)}")
        if cache_create_cost > 0:
            print(f"  Cache create:   {format_cost(cache_create_cost)}")
        if cache_read_cost > 0:
            print(f"  Cache read:     {format_cost(cache_read_cost)}")
        print(f"  TOTAL:          {format_cost(model_cost)}")

    # Grand total
    print("\n" + "=" * 80)
    print("GRAND TOTAL")
    print("=" * 80)
    print(f"  Total requests:      {total_requests:,}")
    print(f"  Total input tokens:  {total_input:,} ({format_number(total_input)})")
    print(f"  Total output tokens: {total_output:,} ({format_number(total_output)})")
    if total_cache_create > 0:
        print(f"  Total cache created: {total_cache_create:,}")
    if total_cache_read > 0:
        print(f"  Total cache read:    {total_cache_read:,}")
    print(f"  ---")
    print(f"  TOTAL COST:          {format_cost(total_cost)}")
    print("=" * 80)


if __name__ == "__main__":
    main()
