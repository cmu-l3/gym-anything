"""
Utility functions for parsing and processing trajectory data from AI agent runs.

This module provides functions to:
- Parse messages.pkl files containing agent-environment interactions
- Extract observations, actions, thoughts, and tool calls
- Load run metadata from info.pkl files
"""

import base64
import gzip
import io
import json
import os
import pickle
import struct
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
from PIL import Image

try:
    from tqdm import tqdm
except ImportError:  # pragma: no cover - optional dependency
    def tqdm(iterable, *args, **kwargs):
        return iterable


# Constants for delta compression
DELTA_FILE = "observations.delta"
COMPRESSED_MARKER = "images_compressed.txt"

# LRU cache for decoded frames (limit to ~10 runs in memory)
_delta_frame_cache: Dict[str, Tuple[List[int], List[np.ndarray]]] = {}
_cache_order: List[str] = []
_MAX_CACHE_RUNS = 10


def _decode_delta_stream(data: bytes) -> List[np.ndarray]:
    """
    Decode delta stream back to list of numpy arrays.
    Returns list of numpy arrays (RGB images).
    """
    if not data:
        return []

    stream = io.BytesIO(data)

    # Read header
    num_frames, h, w, c = struct.unpack('<IIII', stream.read(16))

    # Read first frame (PNG)
    first_len = struct.unpack('<I', stream.read(4))[0]
    first_bytes = stream.read(first_len)
    first_img = Image.open(io.BytesIO(first_bytes))
    frames = [np.array(first_img)]

    # Read and apply deltas
    for i in range(1, num_frames):
        delta_len = struct.unpack('<I', stream.read(4))[0]
        compressed = stream.read(delta_len)
        xor_diff = np.frombuffer(gzip.decompress(compressed), dtype=np.uint8).reshape(h, w, c)
        frame = np.bitwise_xor(frames[-1], xor_diff)
        frames.append(frame)

    return frames


def load_delta_frames(run_dir: Path) -> Tuple[List[int], List[np.ndarray]]:
    """
    Load and decode frames from a delta-compressed run.
    Uses LRU cache to avoid re-decoding.

    Returns:
        Tuple of (step_numbers, frames) where frames are numpy arrays
    """
    global _delta_frame_cache, _cache_order

    run_key = str(run_dir)

    # Check cache first
    if run_key in _delta_frame_cache:
        # Move to end of order (most recently used)
        if run_key in _cache_order:
            _cache_order.remove(run_key)
        _cache_order.append(run_key)
        return _delta_frame_cache[run_key]

    delta_path = run_dir / DELTA_FILE
    if not delta_path.exists():
        return [], []

    try:
        with open(delta_path, 'rb') as f:
            header_line = f.readline().decode('utf-8').strip()
            step_numbers = [int(x) for x in header_line.split(',')]
            encoded = f.read()

        frames = _decode_delta_stream(encoded)

        # Add to cache
        _delta_frame_cache[run_key] = (step_numbers, frames)
        _cache_order.append(run_key)

        # Evict oldest if cache is full
        while len(_cache_order) > _MAX_CACHE_RUNS:
            oldest = _cache_order.pop(0)
            if oldest in _delta_frame_cache:
                del _delta_frame_cache[oldest]

        return step_numbers, frames

    except Exception as e:
        print(f"Error loading delta frames from {run_dir}: {e}")
        return [], []


def get_delta_frame_as_png(run_dir: Path, step_num: int) -> Optional[bytes]:
    """
    Get a single frame from a delta-compressed run as PNG bytes.
    Loads and decodes the delta file on-the-fly with caching.

    Args:
        run_dir: Path to the run directory
        step_num: Step number to retrieve

    Returns:
        PNG bytes or None if not found
    """
    step_numbers, frames = load_delta_frames(run_dir)

    if not step_numbers or not frames:
        return None

    try:
        idx = step_numbers.index(step_num)
        frame = frames[idx]

        # Convert numpy array to PNG bytes
        img = Image.fromarray(frame)
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        return buf.getvalue()

    except (ValueError, IndexError):
        return None


def has_delta_compression(run_dir: Path) -> bool:
    """Check if a run directory has delta-compressed observations."""
    return (run_dir / DELTA_FILE).exists()


def get_delta_step_numbers(run_dir: Path) -> List[int]:
    """Get list of step numbers available in delta file without decoding images."""
    delta_path = run_dir / DELTA_FILE
    if not delta_path.exists():
        return []

    try:
        with open(delta_path, 'rb') as f:
            header_line = f.readline().decode('utf-8').strip()
            return [int(x) for x in header_line.split(',')]
    except Exception:
        return []

def load_messages(messages_pkl_path: str) -> List[Dict[str, Any]]:
    """
    Load messages from a messages.pkl file.
    
    Args:
        messages_pkl_path: Path to the messages.pkl file
        
    Returns:
        List of message dictionaries with 'role' and 'content' keys
    """
    with open(messages_pkl_path, 'rb') as f:
        messages = pickle.load(f)
    return messages


def load_info(info_pkl_path: str) -> Dict[str, Any]:
    """
    Load evaluation info from an info.pkl file.
    
    Args:
        info_pkl_path: Path to the info.pkl file
        
    Returns:
        Dictionary containing evaluation information
    """
    with open(info_pkl_path, 'rb') as f:
        info = pickle.load(f)
    return info


def load_vlm_verifier(run_dir: Path) -> Optional[Dict[str, Any]]:
    """
    Load VLM verifier output if it exists.
    
    Args:
        run_dir: Path to the run directory
        
    Returns:
        Dictionary with 'passed' (bool) and 'feedback' (str), or None if file doesn't exist
    """
    vlm_path = run_dir / "vlm_verifier_output_gpt.json"
    if not vlm_path.exists():
        return None
    
    try:
        with open(vlm_path, 'r') as f:
            data = json.load(f)
            # Ensure passed is boolean
            data['passed'] = bool(data.get('passed', 0))
            return data
    except Exception as e:
        print(f"Error loading VLM verifier from {vlm_path}: {e}")
        return None


def load_owl_responses(responses_json_path: str) -> Dict[str, Any]:
    """
    Load Owl agent responses from responses.json file.
    
    Args:
        responses_json_path: Path to the responses.json file
        
    Returns:
        Dictionary containing model_responses, parsed_responses, and history
    """
    try:
        with open(responses_json_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading Owl responses from {responses_json_path}: {e}")
        return {}


def load_owl_parsed_responses(parsed_responses_json_path: str) -> List[Dict[str, Any]]:
    """
    Load Owl agent parsed responses from parsed_responses.json file.
    
    Args:
        parsed_responses_json_path: Path to the parsed_responses.json file
        
    Returns:
        List of parsed response dictionaries with actions and metadata
    """
    try:
        with open(parsed_responses_json_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading Owl parsed responses from {parsed_responses_json_path}: {e}")
        return []


def load_owl_info(info_json_path: str) -> Dict[str, Any]:
    """
    Load Owl agent info from info.json file.
    
    Args:
        info_json_path: Path to the info.json file
        
    Returns:
        Dictionary containing step, reason, and verifier information
    """
    try:
        with open(info_json_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading Owl info from {info_json_path}: {e}")
        return {}


def is_owl_run(run_dir: Path) -> bool:
    """
    Check if a run directory is from the Owl agent.

    Args:
        run_dir: Path to the run directory

    Returns:
        True if this is an Owl agent run, False otherwise
    """
    return (run_dir / "responses.json").exists() and (run_dir / "info.json").exists()


def is_gpt54_run(run_dir: Path) -> bool:
    """
    Check if a run directory is from the GPT-5.4 Computer Use agent.

    GPT-5.4 runs have responses_metadata.json and action_history.json
    but no messages.pkl or responses.json (the Owl marker).
    """
    return (
        (run_dir / "responses_metadata.json").exists()
        and not (run_dir / "messages.pkl").exists()
        and not is_owl_run(run_dir)
    )


def parse_message_content(content: Any) -> Dict[str, Any]:
    """
    Parse the content of a single message to extract structured information.
    
    Args:
        content: Message content (can be string, list of content blocks, etc.)
        
    Returns:
        Dictionary with parsed information including:
        - text: List of text blocks
        - thinking: List of thinking blocks
        - tool_uses: List of tool use blocks
        - tool_results: List of tool result blocks
        - images: List of image data
    """
    parsed = {
        'text': [],
        'thinking': [],
        'tool_uses': [],
        'tool_results': [],
        'images': []
    }
    
    if isinstance(content, str):
        parsed['text'].append(content)
    elif isinstance(content, list):
        for item in content:
            if hasattr(item, 'type'):
                if item.type == 'text':
                    parsed['text'].append(item.text if hasattr(item, 'text') else str(item))
                elif item.type == 'thinking':
                    parsed['thinking'].append(item.thinking if hasattr(item, 'thinking') else str(item))
                elif item.type == 'tool_use':
                    tool_info = {
                        'name': item.name if hasattr(item, 'name') else None,
                        'id': item.id if hasattr(item, 'id') else None,
                        'input': item.input if hasattr(item, 'input') else None
                    }
                    parsed['tool_uses'].append(tool_info)
                elif item.type == 'tool_result':
                    tool_result = {
                        'tool_use_id': item.tool_use_id if hasattr(item, 'tool_use_id') else None,
                        'content': item.content if hasattr(item, 'content') else None,
                        'is_error': item.is_error if hasattr(item, 'is_error') else False
                    }
                    parsed['tool_results'].append(tool_result)
                elif item.type == 'image':
                    # Extract base64 image data if present
                    if hasattr(item, 'source') and hasattr(item.source, 'data'):
                        parsed['images'].append(item.source.data)
            elif isinstance(item, dict):
                # Handle dictionary-based content blocks
                if item.get('type') == 'text':
                    parsed['text'].append(item.get('text', ''))
                elif item.get('type') == 'image':
                    if 'source' in item and 'data' in item['source']:
                        parsed['images'].append(item['source']['data'])
                elif item.get('type') == 'tool_result':
                    parsed['tool_results'].append(item)
                elif item.get('type') == 'tool_use':
                    parsed['tool_uses'].append(item)
    
    return parsed


def extract_owl_trajectory_steps(parsed_responses: List[Dict[str, Any]], run_dir: Path) -> List[Dict[str, Any]]:
    """
    Extract trajectory steps from Owl agent parsed responses.

    Args:
        parsed_responses: List of parsed response dictionaries from parsed_responses.json
        run_dir: Path to the run directory

    Returns:
        List of step dictionaries with observation, thinking, actions, etc.
    """
    steps = []

    # Check if this run uses delta compression
    delta_compressed = has_delta_compression(run_dir)
    delta_steps = get_delta_step_numbers(run_dir) if delta_compressed else []

    for step_num, parsed in enumerate(parsed_responses):
        # Find corresponding observation
        obs_path = run_dir / f"observation_{step_num}.png"
        if not obs_path.exists():
            # Check if available in delta compression
            if delta_compressed and step_num in delta_steps:
                # Keep the path - /api/image will decompress on-the-fly
                pass
            else:
                obs_path = None
        
        # Extract thinking and conclusion from metadata
        metadata = parsed.get('metadata', {})
        thinking = metadata.get('thought', '').strip()
        conclusion = metadata.get('conclusion', '').strip()
        
        # Format actions
        actions = parsed.get('actions', [])
        tool_calls_formatted = []
        
        if actions:
            for action in actions:
                if 'mouse' in action:
                    mouse_action = action['mouse']
                    if 'left_click' in mouse_action:
                        coords = mouse_action['left_click']
                        tool_calls_formatted.append(f"Mouse Left Click: ({coords[0]}, {coords[1]})")
                    elif 'right_click' in mouse_action:
                        coords = mouse_action['right_click']
                        tool_calls_formatted.append(f"Mouse Right Click: ({coords[0]}, {coords[1]})")
                    elif 'double_click' in mouse_action:
                        coords = mouse_action['double_click']
                        tool_calls_formatted.append(f"Mouse Double Click: ({coords[0]}, {coords[1]})")
                    elif 'move' in mouse_action:
                        coords = mouse_action['move']
                        tool_calls_formatted.append(f"Mouse Move: ({coords[0]}, {coords[1]})")
                elif 'keyboard' in action:
                    kb_action = action['keyboard']
                    if 'text' in kb_action:
                        tool_calls_formatted.append(f"Type Text: '{kb_action['text']}'")
                    elif 'key' in kb_action:
                        tool_calls_formatted.append(f"Key Press: {kb_action['key']}")
        elif metadata.get('is_terminal'):
            status = metadata.get('status', 'unknown')
            tool_calls_formatted.append(f"Terminate - Status: {status}")
        
        # If no actions and not terminal, indicate wait/no-op
        if not tool_calls_formatted and not metadata.get('is_terminal'):
            tool_calls_formatted.append("No action taken")
        
        step = {
            'step_num': step_num,
            'observation_path': obs_path,
            'thinking': thinking,
            'text_response': conclusion,
            'tool_calls': tool_calls_formatted,
            'tool_outputs': [],  # Owl doesn't have explicit tool outputs
            'raw_response': f"Step {step_num + 1}: {conclusion}"  # Use conclusion as raw response
        }
        
        steps.append(step)
    
    return steps


def _format_gpt54_action(action) -> str:
    """Format a GPT-5.4 action into a readable string.

    Handles both the new dict format (with full details) and the old
    plain-string format (just the action type) for backward compatibility.
    """
    if isinstance(action, str):
        # Old format: just the type name
        return f"GPT Action: {action}"

    atype = action.get('type', 'unknown')
    if atype == 'click':
        button = action.get('button', 'left')
        return f"Click ({button}): ({action.get('x')}, {action.get('y')})"
    elif atype == 'double_click':
        return f"Double Click: ({action.get('x')}, {action.get('y')})"
    elif atype == 'move':
        return f"Mouse Move: ({action.get('x')}, {action.get('y')})"
    elif atype == 'scroll':
        return f"Scroll: ({action.get('x')}, {action.get('y')}) delta={action.get('scrollY', 0)}"
    elif atype == 'keypress':
        keys = action.get('keys', [])
        return f"Key Press: {'+'.join(keys)}"
    elif atype == 'type':
        text = action.get('text', '')
        display = text[:80] + '...' if len(text) > 80 else text
        return f"Type: '{display}'"
    elif atype == 'drag':
        return (f"Drag: ({action.get('startX')}, {action.get('startY')}) "
                f"-> ({action.get('endX')}, {action.get('endY')})")
    elif atype == 'wait':
        return f"Wait: {action.get('time', 2.0)}s"
    elif atype == 'screenshot':
        return "Screenshot"
    return f"GPT Action: {atype}"


def extract_gpt54_trajectory_steps(responses_metadata: List[Dict[str, Any]],
                                    action_history: List[Dict[str, Any]],
                                    run_dir: Path) -> List[Dict[str, Any]]:
    """
    Extract trajectory steps from GPT-5.4 Computer Use agent data.

    Args:
        responses_metadata: List of response metadata dicts from responses_metadata.json
        action_history: List of action history dicts from action_history.json
        run_dir: Path to the run directory

    Returns:
        List of step dictionaries compatible with the trajectory viewer.
    """
    steps = []

    delta_compressed = has_delta_compression(run_dir)
    delta_steps = get_delta_step_numbers(run_dir) if delta_compressed else []

    # Build a lookup from step number to action_history entry
    action_by_step = {entry['step']: entry for entry in action_history}

    # The number of steps is driven by action_history (one entry per agent step).
    # responses_metadata may have extra entries (internal screenshot loops),
    # so we align by index but cap at the length of the shorter list.
    num_steps = max(
        (max((e['step'] for e in action_history), default=-1) + 1) if action_history else 0,
        len(responses_metadata),
    )

    for step_num in range(num_steps):
        # Observation image
        obs_path = run_dir / f"observation_{step_num}.png"
        if not obs_path.exists():
            if delta_compressed and step_num in delta_steps:
                pass  # /api/image will decompress on-the-fly
            else:
                obs_path = None

        # Text output and thinking from responses_metadata (if available for this step)
        text_response = ''
        thinking = ''
        if step_num < len(responses_metadata):
            text_response = responses_metadata[step_num].get('text_output', '')
            thinking = responses_metadata[step_num].get('thinking', '')

        # Actions from action_history
        action_entry = action_by_step.get(step_num, {})
        gpt_actions = action_entry.get('gpt_actions', [])
        tool_calls_formatted = [_format_gpt54_action(a) for a in gpt_actions] if gpt_actions else []

        if not tool_calls_formatted and not text_response:
            tool_calls_formatted.append("No action taken")

        steps.append({
            'step_num': step_num,
            'observation_path': obs_path,
            'thinking': thinking,
            'text_response': text_response,
            'tool_calls': tool_calls_formatted,
            'tool_outputs': [],
        })

    return steps


def extract_trajectory_steps(messages: List[Dict[str, Any]], run_dir: Path) -> List[Dict[str, Any]]:
    """
    Extract step-by-step trajectory information from messages.
    
    Args:
        messages: List of messages from messages.pkl
        run_dir: Path to the run directory containing observation images
        
    Returns:
        List of step dictionaries, each containing:
        - step_num: Step number
        - observation_path: Path to observation image
        - thinking: Agent's thinking/reasoning
        - text_response: Agent's text response
        - tool_calls: List of tool calls made
        - tool_outputs: List of tool outputs received
    """
    steps = []
    current_step = -1

    # Find all observation images (either as files or in delta compression)
    observation_files = sorted(run_dir.glob('observation_*.png'))
    observation_map = {}

    if observation_files:
        for obs_file in observation_files:
            # Extract step number from filename
            step_num = int(obs_file.stem.split('_')[1])
            observation_map[step_num] = obs_file
    elif has_delta_compression(run_dir):
        # Build virtual observation map from delta file
        for step_num in get_delta_step_numbers(run_dir):
            # Create path that /api/image will decompress on-the-fly
            observation_map[step_num] = run_dir / f"observation_{step_num}.png"
    
    # Process messages
    i = 0
    while i < len(messages):
        msg = messages[i]
        role = msg.get('role', '')
        content = msg.get('content', '')
        
        if role == 'user' and i == 0:
            # First message is the task description
            i += 1
            continue
        
        if role == 'assistant':
            # This is an agent response
            current_step += 1
            
            step_info = {
                'step_num': current_step,
                'observation_path': observation_map.get(current_step, None),
                'thinking': [],
                'text_response': [],
                'tool_calls': [],
                'tool_outputs': []
            }
            
            # Parse assistant content
            parsed = parse_message_content(content)
            step_info['thinking'] = parsed['thinking']
            step_info['text_response'] = parsed['text']
            step_info['tool_calls'] = parsed['tool_uses']
            
            # Look ahead for tool results in next user message
            if i + 1 < len(messages) and messages[i + 1].get('role') == 'user':
                next_content = messages[i + 1].get('content', '')
                next_parsed = parse_message_content(next_content)
                step_info['tool_outputs'] = next_parsed['tool_results']
            
            steps.append(step_info)
        
        i += 1
    
    return steps


def get_all_runs(base_dir: str = "all_runs", constraint: str = None) -> List[Dict[str, str]]:
    """
    Scan the all_runs directory and return a list of all available runs.
    
    Args:
        base_dir: Base directory containing all runs
        
    Returns:
        List of dictionaries with run metadata:
        - experiment: Experiment name
        - model: Model name
        - task: Task name
        - run_number: Run number
        - run_path: Full path to run directory
    """
    runs = []
    base_path = Path(base_dir)
    
    if not base_path.exists():
        return runs
    
    # Structure: all_runs/<experiment>/<model>/<task>/run_<num>/
    # Note: Owl has nested models: <experiment>/<vendor>/<model>/<task>/run_<num>/
    for exp_dir in tqdm(base_path.iterdir()):
        if not exp_dir.is_dir():
            continue
        if constraint and constraint not in exp_dir.name:
            continue
        experiment = exp_dir.name
        
        for model_dir in exp_dir.iterdir():
            if not model_dir.is_dir():
                continue
            model = model_dir.name
            for task_dir in tqdm(model_dir.iterdir()):
                if not task_dir.is_dir():
                    continue
                task = task_dir.name
                
                # Check if this level contains run_* directories (standard structure)
                # or if it's another nesting level (Owl structure)
                # Note: Filter to only directories named run_<number> to avoid matching
                # task names like "run_failing_tests"
                run_dirs = []
                for d in task_dir.glob('run_*'):
                    if not d.is_dir():
                        continue
                    try:
                        int(d.name.split('_')[1])  # Must be run_<number>
                        run_dirs.append(d)
                    except (ValueError, IndexError):
                        continue

                if run_dirs:
                    # Standard structure: experiment/model/task/run_*
                    for run_dir in run_dirs:
                        run_number = int(run_dir.name.split('_')[1])
                        # Verify this is a valid run directory (Claude, Owl, or GPT-5.4)
                        if (run_dir / 'messages.pkl').exists() or (run_dir / 'responses.json').exists() or (run_dir / 'responses_metadata.json').exists():
                            runs.append({
                                'experiment': experiment,
                                'model': model,
                                'task': task,
                                'run_number': run_number,
                                'run_path': str(run_dir)
                            })
                else:
                    # Nested structure: experiment/vendor/model/task/run_*
                    # task_dir is actually another model level
                    for actual_task_dir in tqdm(task_dir.iterdir()):
                        if not actual_task_dir.is_dir():
                            continue
                        actual_task = actual_task_dir.name

                        for run_dir in actual_task_dir.glob('run_*'):
                            if not run_dir.is_dir():
                                continue

                            try:
                                run_number = int(run_dir.name.split('_')[1])
                            except (ValueError, IndexError):
                                continue

                            # Verify this is a valid run directory
                            if (run_dir / 'messages.pkl').exists() or (run_dir / 'responses.json').exists() or (run_dir / 'responses_metadata.json').exists():
                                # Combine model path for nested structure
                                combined_model = f"{model}/{task}"
                                runs.append({
                                    'experiment': experiment,
                                    'model': combined_model,
                                    'task': actual_task,
                                    'run_number': run_number,
                                    'run_path': str(run_dir)
                                })
    
    return sorted(runs, key=lambda x: (x['experiment'], x['model'], x['task'], x['run_number']))


def format_tool_call(tool_call: Dict[str, Any]) -> str:
    """
    Format a tool call into a readable string.
    Uses Unicode symbols that are widely supported across fonts.
    
    Args:
        tool_call: Tool call dictionary
        
    Returns:
        Formatted string representation
    """
    name = tool_call.get('name', 'unknown')
    tool_input = tool_call.get('input', {})
    
    if isinstance(tool_input, dict):
        action = tool_input.get('action', 'N/A')
        
        # Use Unicode symbols that are widely supported (not emojis)
        # These are in the standard Unicode blocks that most fonts include
        if action == 'screenshot':
            return f"◉ SCREENSHOT: Take Screenshot"
        elif action == 'click':
            coord = tool_input.get('coordinate', [0, 0])
            return f"► CLICK: at ({coord[0]}, {coord[1]})"
        elif action == 'type':
            text = tool_input.get('text', '')[:50]
            return f"⌨ TYPE: '{text}'"
        elif action == 'key':
            keys = tool_input.get('text', [])
            return f"⌨ KEY: Press {keys}"
        elif action == 'scroll':
            pixels = tool_input.get('pixels', 0)
            direction = "up" if pixels > 0 else "down"
            symbol = "↑" if pixels > 0 else "↓"
            return f"{symbol} SCROLL: {direction} ({abs(pixels)} pixels)"
        elif action == 'wait':
            time = tool_input.get('time', 1)
            return f"⧖ WAIT: {time}s"
        else:
            return f"● ACTION: {action}: {str(tool_input)[:50]}"
    
    return f"● {name}: {str(tool_input)[:50]}"


def get_run_summary(run_path: str) -> Dict[str, Any]:
    """
    Get a summary of a run including final result and statistics.
    
    Args:
        run_path: Path to run directory
        
    Returns:
        Dictionary with run summary
    """
    run_dir = Path(run_path)
    summary = {
        'run_path': run_path,
        'total_steps': 0,
        'success': None,
        'score': None,
        'feedback': None,
        'reason': None,
        'is_owl': is_owl_run(run_dir)
    }
    
    # Load info from either info.pkl (Claude) or info.json (Owl)
    info_pkl_path = run_dir / 'info.pkl'
    info_json_path = run_dir / 'info.json'
    
    if info_pkl_path.exists():
        info = load_info(str(info_pkl_path))
        summary['reason'] = info.get('reason', 'Unknown')
        
        if 'verifier' in info and isinstance(info['verifier'], dict):
            verifier = info['verifier']
            summary['success'] = verifier.get('passed', None)
            summary['score'] = verifier.get('score', None)
            summary['feedback'] = verifier.get('feedback', None)
    elif info_json_path.exists():
        info = load_owl_info(str(info_json_path))
        summary['reason'] = info.get('reason', 'Unknown')
        
        if 'verifier' in info and isinstance(info['verifier'], dict):
            verifier = info['verifier']
            summary['success'] = verifier.get('passed', None)
            summary['score'] = verifier.get('score', None)
            summary['feedback'] = verifier.get('feedback', None)
    
    # Count observation files to get total steps
    observation_files = list(run_dir.glob('observation_*.png'))
    if observation_files:
        summary['total_steps'] = len(observation_files)
    elif has_delta_compression(run_dir):
        # Get step count from delta file
        summary['total_steps'] = len(get_delta_step_numbers(run_dir))
    else:
        summary['total_steps'] = 0

    return summary


def compute_experiment_statistics(experiment: str, model: str, base_path: str = "all_runs") -> Dict[str, Any]:
    """
    Compute comprehensive statistics for a specific experiment-model pair.
    
    Args:
        experiment: Experiment name
        model: Model name
        base_path: Base directory for runs
        
    Returns:
        Dictionary containing various statistics
    """
    from collections import defaultdict
    import numpy as np
    
    exp_path = Path(base_path) / experiment / model
    if not exp_path.exists():
        return {}
    
    # Group runs by task
    task_runs = defaultdict(list)
    
    for task_dir in exp_path.iterdir():
        if not task_dir.is_dir():
            continue
        task_name = task_dir.name
        
        # Collect all runs for this task
        runs = []
        for run_dir in task_dir.glob("run_*"):
            info_pkl = run_dir / "info.pkl"
            info_json = run_dir / "info.json"
            
            # Skip if neither info file exists
            if not info_pkl.exists() and not info_json.exists():
                continue
            
            try:
                # Load info from either pkl or json format
                if info_pkl.exists():
                    info = load_info(str(info_pkl))
                else:
                    info = load_owl_info(str(info_json))
                
                # Count steps (number of observation files or delta frames)
                obs_files = list(run_dir.glob("observation_*.png"))
                if obs_files:
                    obs_count = len(obs_files)
                elif has_delta_compression(run_dir):
                    obs_count = len(get_delta_step_numbers(run_dir))
                else:
                    obs_count = 0
                
                # Handle cases where verifier is None (task errored before verification)
                verifier = info.get('verifier', {}) if info else {}
                if verifier is None:
                    verifier = {}
                # breakpoint()
                
                # Load VLM verifier data
                vlm_verifier = load_vlm_verifier(run_dir)
                
                run_data = {
                    'run_dir': str(run_dir),
                    'run_number': int(run_dir.name.split('_')[1]),
                    'passed': verifier.get('passed', False),
                    'score': verifier.get('score', 0),
                    # 'steps': info.get('step', obs_count) if info else obs_count,
                    'steps': obs_count, # TODO: Ideally, could have been the step number from env.
                    'reason': info.get('reason', '') if info else '',
                    'feedback': verifier.get('feedback', ''),
                    'has_verifier': verifier != {},
                    # VLM verifier data
                    'vlm_passed': vlm_verifier.get('passed', None) if vlm_verifier else None,
                    'vlm_feedback': vlm_verifier.get('feedback', '') if vlm_verifier else '',
                    'has_vlm_verifier': vlm_verifier is not None,
                    # Track if this is an Owl run
                    'is_owl': is_owl_run(run_dir)
                }
                runs.append(run_data)
            except Exception as e:
                print(f"Error loading {run_dir}: {e}")
                continue
        
        if runs:
            # Sort by run_number and store
            runs.sort(key=lambda x: x['run_number'])
            task_runs[task_name] = runs
    
    # Compute statistics
    stats = {
        'experiment': experiment,
        'model': model,
        'total_tasks': len(task_runs),
        'total_runs': sum(len(runs) for runs in task_runs.values()),
    }
    
    # Count tasks with/without verifier
    tasks_with_verifier = sum(1 for runs in task_runs.values() if runs[-1].get('has_verifier', True))
    tasks_without_verifier = len(task_runs) - tasks_with_verifier
    stats['tasks_with_verifier'] = tasks_with_verifier
    stats['tasks_without_verifier'] = tasks_without_verifier
    stats['error_rate'] = (tasks_without_verifier / len(task_runs) * 100) if task_runs else 0
    
    # Pass @ 1 (latest run only)
    latest_runs = [runs[-1] for runs in task_runs.values() if runs]
    if latest_runs:
        passed_count = sum(1 for r in latest_runs if r['passed'])
        stats['pass_at_1'] = (passed_count / len(latest_runs)) * 100
        stats['pass_at_1_count'] = f"{passed_count}/{len(latest_runs)}"
        
        # Average score (latest runs)
        scores = [r['score'] for r in latest_runs]
        stats['avg_score'] = np.mean(scores) if scores else 0
        stats['median_score'] = np.median(scores) if scores else 0
        stats['std_score'] = np.std(scores) if scores else 0
        stats['score_p25'] = np.percentile(scores, 25) if scores else 0
        stats['score_p75'] = np.percentile(scores, 75) if scores else 0
        
        # Average steps (latest runs)
        steps_all = [r['steps'] for r in latest_runs]
        stats['avg_steps'] = np.mean(steps_all) if steps_all else 0
        stats['median_steps'] = np.median(steps_all) if steps_all else 0
        stats['std_steps'] = np.std(steps_all) if steps_all else 0
        
        # Steps for successful vs failed
        successful_steps = [r['steps'] for r in latest_runs if r['passed']]
        failed_steps = [r['steps'] for r in latest_runs if not r['passed']]
        stats['avg_steps_successful'] = np.mean(successful_steps) if successful_steps else 0
        stats['avg_steps_failed'] = np.mean(failed_steps) if failed_steps else 0
    else:
        stats['pass_at_1'] = 0
        stats['pass_at_1_count'] = "0/0"
        stats['avg_score'] = 0
        stats['median_score'] = 0
        stats['avg_steps'] = 0
        stats['median_steps'] = 0
        stats['avg_steps_successful'] = 0
        stats['avg_steps_failed'] = 0
    
    # Pass @ k for different k values
    for k in [2, 3, 5]:
        # Pass@k: at least one pass in best k runs per task
        pass_at_k_count = 0
        for task_name, runs in task_runs.items():
            # Take best k runs (sorted by score)
            best_k = sorted(runs, key=lambda x: x['score'], reverse=True)[:k]
            if any(r['passed'] for r in best_k):
                pass_at_k_count += 1
        
        if task_runs:
            stats[f'pass_at_{k}'] = (pass_at_k_count / len(task_runs)) * 100
            stats[f'pass_at_{k}_count'] = f"{pass_at_k_count}/{len(task_runs)}"
        else:
            stats[f'pass_at_{k}'] = 0
            stats[f'pass_at_{k}_count'] = "0/0"
    
    # Score distribution (for histogram)
    if latest_runs:
        stats['score_distribution'] = [r['score'] for r in latest_runs]
        stats['steps_distribution'] = [r['steps'] for r in latest_runs]
    else:
        stats['score_distribution'] = []
        stats['steps_distribution'] = []
    
    # VLM Verifier Statistics
    vlm_runs = [r for r in latest_runs if r.get('has_vlm_verifier', False)]
    stats['vlm_tasks_count'] = len(vlm_runs)
    stats['vlm_coverage'] = (len(vlm_runs) / len(latest_runs) * 100) if latest_runs else 0
    
    if vlm_runs:
        vlm_passed_count = sum(1 for r in vlm_runs if r.get('vlm_passed', False))
        stats['vlm_pass_rate'] = (vlm_passed_count / len(vlm_runs)) * 100
        stats['vlm_pass_count'] = f"{vlm_passed_count}/{len(vlm_runs)}"
        
        # Agreement analysis (only for tasks that have both verifiers)
        both_verifiers = [r for r in vlm_runs if r.get('has_verifier', True)]
        if both_verifiers:
            agreements = sum(1 for r in both_verifiers if r['passed'] == r['vlm_passed'])
            stats['vlm_agreement_rate'] = (agreements / len(both_verifiers)) * 100
            stats['vlm_agreement_count'] = f"{agreements}/{len(both_verifiers)}"
            
            # Disagreement breakdown
            vlm_pass_original_fail = sum(1 for r in both_verifiers if r['vlm_passed'] and not r['passed'])
            vlm_fail_original_pass = sum(1 for r in both_verifiers if not r['vlm_passed'] and r['passed'])
            stats['vlm_pass_original_fail'] = vlm_pass_original_fail
            stats['vlm_fail_original_pass'] = vlm_fail_original_pass
        else:
            stats['vlm_agreement_rate'] = 0
            stats['vlm_agreement_count'] = "0/0"
            stats['vlm_pass_original_fail'] = 0
            stats['vlm_fail_original_pass'] = 0
    else:
        stats['vlm_pass_rate'] = 0
        stats['vlm_pass_count'] = "0/0"
        stats['vlm_agreement_rate'] = 0
        stats['vlm_agreement_count'] = "0/0"
        stats['vlm_pass_original_fail'] = 0
        stats['vlm_fail_original_pass'] = 0
    
    # Task-level breakdown
    task_stats = []
    error_trajectories = []
    successful_trajectories = []
    failed_trajectories = []
    disagreement_trajectories = []
    
    for task_name, runs in sorted(task_runs.items()):
        latest = runs[-1]
        task_stats.append({
            'task': task_name,
            'passed': latest['passed'],
            'score': latest['score'],
            'steps': latest['steps'],
            'total_runs': len(runs),
            'best_score': max(r['score'] for r in runs),
            'any_passed': any(r['passed'] for r in runs)
        })
        
        # Track different trajectory types
        if not latest.get('has_verifier', True):
            # Error trajectories (tasks without verifier)
            error_trajectories.append({
                'task': task_name,
                'run_dir': latest['run_dir'],
                'steps': latest['steps'],
                'reason': latest['reason'],
                'run_number': latest['run_number'],
                'score': latest['score']
            })
        elif latest['passed']:
            # Successful trajectories
            successful_trajectories.append({
                'task': task_name,
                'run_dir': latest['run_dir'],
                'steps': latest['steps'],
                'score': latest['score'],
                'run_number': latest['run_number'],
                'feedback': latest.get('feedback', '')
            })
        else:
            # Failed trajectories (verified but didn't pass)
            failed_trajectories.append({
                'task': task_name,
                'run_dir': latest['run_dir'],
                'steps': latest['steps'],
                'score': latest['score'],
                'run_number': latest['run_number'],
                'feedback': latest.get('feedback', '')
            })
        
        # Track disagreements (where VLM and original verifier disagree)
        if latest.get('has_vlm_verifier', False) and latest.get('has_verifier', True):
            if latest['passed'] != latest['vlm_passed']:
                disagreement_type = 'vlm_pass_original_fail' if latest['vlm_passed'] else 'vlm_fail_original_pass'
                disagreement_trajectories.append({
                    'task': task_name,
                    'run_dir': latest['run_dir'],
                    'steps': latest['steps'],
                    'score': latest['score'],
                    'run_number': latest['run_number'],
                    'original_passed': latest['passed'],
                    'vlm_passed': latest['vlm_passed'],
                    'original_feedback': latest.get('feedback', ''),
                    'vlm_feedback': latest.get('vlm_feedback', ''),
                    'disagreement_type': disagreement_type
                })
    
    stats['task_breakdown'] = task_stats
    stats['error_trajectories'] = error_trajectories
    stats['successful_trajectories'] = successful_trajectories
    stats['failed_trajectories'] = failed_trajectories
    stats['disagreement_trajectories'] = disagreement_trajectories
    
    return stats


def compare_experiments(experiment_model_pairs: List[Tuple[str, str]], base_path: str = "all_runs") -> Dict[str, Any]:
    """
    Compare statistics across multiple experiment-model pairs.
    
    Args:
        experiment_model_pairs: List of (experiment, model) tuples
        base_path: Base directory for runs
        
    Returns:
        Dictionary with comparison data
    """
    comparisons = []
    
    for experiment, model in experiment_model_pairs:
        stats = compute_experiment_statistics(experiment, model, base_path)
        if stats:
            stats['label'] = f"{experiment}/{model}"
            comparisons.append(stats)
    
    # Add head-to-head comparison if we have exactly 2 experiments
    head_to_head = None
    if len(comparisons) == 2:
        head_to_head = compute_head_to_head(comparisons[0], comparisons[1], base_path)
    
    return {
        'comparisons': comparisons,
        'count': len(comparisons),
        'head_to_head': head_to_head
    }


def compute_head_to_head(stats1: Dict[str, Any], stats2: Dict[str, Any], base_path: str) -> Dict[str, Any]:
    """
    Compute head-to-head comparison between two experiments.
    
    Args:
        stats1: Statistics for first experiment
        stats2: Statistics for second experiment
        base_path: Base directory
        
    Returns:
        Head-to-head comparison metrics
    """
    # Get common tasks
    tasks1 = {t['task']: t for t in stats1.get('task_breakdown', [])}
    tasks2 = {t['task']: t for t in stats2.get('task_breakdown', [])}
    common_tasks = set(tasks1.keys()) & set(tasks2.keys())
    
    if not common_tasks:
        return None
    
    # Compare on common tasks
    model1_wins = 0
    model2_wins = 0
    ties = 0
    task_comparisons = []
    
    for task in sorted(common_tasks):
        t1 = tasks1[task]
        t2 = tasks2[task]
        
        # Determine winner based on score
        if t1['score'] > t2['score']:
            winner = stats1['label']
            model1_wins += 1
        elif t2['score'] > t1['score']:
            winner = stats2['label']
            model2_wins += 1
        else:
            winner = 'Tie'
            ties += 1
        
        task_comparisons.append({
            'task': task,
            'model1_score': t1['score'],
            'model2_score': t2['score'],
            'model1_passed': t1['passed'],
            'model2_passed': t2['passed'],
            'model1_steps': t1['steps'],
            'model2_steps': t2['steps'],
            'winner': winner,
            'score_diff': abs(t1['score'] - t2['score'])
        })
    
    # Sort by score difference (biggest differences first)
    task_comparisons.sort(key=lambda x: x['score_diff'], reverse=True)
    
    return {
        'model1': stats1['label'],
        'model2': stats2['label'],
        'common_tasks': len(common_tasks),
        'model1_wins': model1_wins,
        'model2_wins': model2_wins,
        'ties': ties,
        'model1_win_rate': (model1_wins / len(common_tasks) * 100) if common_tasks else 0,
        'model2_win_rate': (model2_wins / len(common_tasks) * 100) if common_tasks else 0,
        'task_comparisons': task_comparisons
    }
