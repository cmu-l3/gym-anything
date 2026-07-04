from agents.agents.base import BaseAgent
from agents.shared.prompts import CLAUDE_SYSTEM_PROMPT, CLAUDE_SYSTEM_PROMPT_CAREFUL
from agents.shared.llm_clients import call_claude, claude_parse_tool_result
from agents.shared.message_cache import add_cache_blocks
from PIL import Image
import base64
from pathlib import Path
import pickle
import logging
import os
from glob import glob
from io import BytesIO


# Resolution at which screenshots are SENT to Claude. Must match the
# display_{width,height}_px declared in agents/shared/llm_clients.py:call_claude.
# Coordinates Claude returns in this 1280x720 space are scaled back up to the
# env's native 1920x1080 via convert_point_format_claude (default coord_scale
# in claude_parse_tool_result).
_SEND_W, _SEND_H = 1280, 720


class ClaudeFixedAgent(BaseAgent):


    def setup_custom_logger(self):
        task_name = self.agent_args.get('task_name', 'task')
        self.save_folder_custom = f'all_runs/{self.exp_name}/{self.model}/{task_name}'
        for run_number in range(0, 100):
            if os.path.exists(f'{self.save_folder_custom}/run_{run_number}'):
                continue
            self.save_folder_custom = f'{self.save_folder_custom}/run_{run_number}'
            break
        os.makedirs(self.save_folder_custom, exist_ok=False)

    def save_observation(self, observation):
        Image.open(observation['screen']['path']).save(f'{self.save_folder_custom}/observation_{self.step_idx}.png')

    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get('agent_args', {})
        self.model = self.agent_args.get('model', 'claude-sonnet-4-20250514')
        self.decoding_params = self.agent_args.get('decoding_params', {})

        self.exp_name = self.agent_args.get('exp_name', 'exp')
        self.setup_custom_logger()

        self.messages = []
        system_prompt_type = self.agent_args.get('system_prompt_type', 'CLAUDE_SYSTEM_PROMPT')
        self.system_prompt = eval(system_prompt_type)

        self.done = False
        self.step_idx = -1

        self.images_to_keep = self.agent_args.get('images_to_keep', 7)
        self.min_removal_threshold = self.agent_args.get('min_removal_threshold', 7)

        self.debug = kwargs.get('debug', False)
        self.verbose = kwargs.get('verbose', False)


    def init(self, task_description, display_resolution, save_path):
        self.task_description = task_description
        self.display_resolution = display_resolution
        self.save_path = save_path
        self.messages.append({"content": self.task_description, "role": "user"})


    def step(self, obs, action_outputs):

        self.save_observation(obs)

        self.step_idx += 1
        if len(action_outputs) > 0:
            # Per-action obs: if run_single attached an "obs" field to each
            # action_output (post-this-tool_use observation), _convert_action_outputs
            # uses it. Otherwise it falls back to the final-turn obs.
            fallback_b64 = self._obs_to_base64(obs)
            converted_action_outputs = self._convert_action_outputs(action_outputs, fallback_b64)
            self.messages.append({"content": converted_action_outputs, "role": "user"})

        self._filter_old_images()
        self.messages = add_cache_blocks(self.messages)

        response = call_claude(self.messages, self.model, self.decoding_params.get('temperature', 1.0), self.decoding_params.get('top_p', 0.95), self.decoding_params.get('thinking_budget', 8192), self.system_prompt)
        response_content = response.content
        self.messages.append({'role': 'assistant', 'content': response_content})
        actions = self._get_actions_from_response(response_content)

        # Distinguish "Claude returned text only (natural termination)" from
        # "Claude returned tool_uses but they failed to parse (turn rolled
        # back, trajectory continues)". Only the former should set done.
        had_tool_uses = any(
            getattr(block, 'type', None) == 'tool_use' for block in response_content
        )
        if not had_tool_uses and len(actions) == 0:
            self.done = True

        return actions

    def finish(self, *args, **kwargs):
        pickle.dump(self.messages, open(f'{self.save_path}/messages.pkl', 'wb'))
        pickle.dump(self.messages, open(f'{self.save_folder_custom}/messages.pkl', 'wb'))

        if 'info' in kwargs:
            info = kwargs['info']
            pickle.dump(info, open(f'{self.save_folder_custom}/info.pkl', 'wb'))

    # ---- Fix 1: Screenshot feedback after every action ----

    def _obs_to_base64(self, obs):
        """Resize the observation screenshot to 1280x720 (matching the
        display dims declared in call_claude) and return as base64 PNG.

        Sending 1280x720 cuts image token cost roughly in half versus native
        1920x1080 (~1,230 vs ~2,765 tokens per image). Coordinates returned
        by Claude in this 1280x720 space are mapped to the env's native
        1920x1080 by convert_point_format_claude (the parser's default
        coord_scale)."""
        image = Image.open(obs['screen']['path'])
        if image.size != (_SEND_W, _SEND_H):
            image = image.resize((_SEND_W, _SEND_H))
        buffered = BytesIO()
        image.save(buffered, format="PNG")
        return base64.b64encode(buffered.getvalue()).decode()

    # ---- Fix 2: Filter old images from context ----

    def _filter_old_images(self):
        """Remove old screenshots from messages, keeping only the N most recent.
        Ported from computer-use-demo's _maybe_filter_to_n_most_recent_images."""
        if self.images_to_keep is None or self.images_to_keep <= 0:
            return

        tool_result_blocks = [
            item
            for message in self.messages
            for item in (message["content"] if isinstance(message["content"], list) else [])
            if isinstance(item, dict) and item.get("type") == "tool_result"
        ]

        total_images = sum(
            1
            for tool_result in tool_result_blocks
            for content in tool_result.get("content", [])
            if isinstance(content, dict) and content.get("type") == "image"
        )

        images_to_remove = total_images - self.images_to_keep
        images_to_remove -= images_to_remove % self.min_removal_threshold

        if images_to_remove <= 0:
            return

        for tool_result in tool_result_blocks:
            if isinstance(tool_result.get("content"), list):
                new_content = []
                for content in tool_result.get("content", []):
                    if isinstance(content, dict) and content.get("type") == "image":
                        if images_to_remove > 0:
                            images_to_remove -= 1
                            continue
                    new_content.append(content)
                tool_result["content"] = new_content

    # ---- Action parsing ----

    def _get_actions_from_response(self, response_content):
        """Parse every tool_use block in the assistant response, all-or-nothing.

        If every tool_use parses cleanly, returns the full action group list
        for the env to execute in order.

        If ANY tool_use fails to parse, we adopt atomic-turn semantics: execute
        none of them, append an `is_error=True` tool_result for every tool_use
        in the turn so the API contract (one tool_result per tool_use_id) holds,
        keep `self.done = False` so the trajectory survives, and return [] so
        run_single skips the env-step phase for this turn. The model sees the
        error tool_results on its next call and can retry.
        """
        # First pass: collect tool_use blocks and their parse outcomes
        # without committing anything to the action list yet.
        parsed = []  # list of (tool_id, actions_or_None, error_str_or_None)
        for block in response_content:
            if block.type == "thinking":
                if self.verbose:
                    print(f"Thinking: {block.thinking}")
                continue
            if block.type == "text":
                if self.verbose:
                    print(f"Response: {block.text}")
                continue
            if block.type != "tool_use":
                continue
            tool_id = block.id
            try:
                # Default coord_scale = convert_point_format_claude, which
                # maps Claude's 1280x720-space coords to the env's 1920x1080.
                actions = claude_parse_tool_result(block.input)
                parsed.append((tool_id, actions, None))
                if self.verbose:
                    print(f"Actions: {actions} ; Tool ID: {tool_id}")
            except Exception as e:
                err = f"{type(e).__name__}: {e}"
                parsed.append((tool_id, None, err))
                print(f"Parse error on tool_use {tool_id}: {err}")
                if self.debug:
                    breakpoint()

        any_errors = any(err is not None for (_, _, err) in parsed)
        if any_errors:
            # Atomic-turn rollback: emit error tool_results for *every*
            # tool_use in the turn (API requires one tool_result per
            # tool_use_id) and keep the trajectory alive.
            self._emit_turn_parse_error(parsed)
            return []

        return [
            {'tool_id': tool_id, 'actions': actions}
            for (tool_id, actions, _) in parsed
        ]

    def _emit_turn_parse_error(self, parsed):
        """Append a user message of error tool_results for the failed turn.

        `parsed` is a list of (tool_id, actions, error_str). One tool_result
        per entry is emitted; entries whose own parse succeeded get a message
        explaining they were rolled back because a sibling tool_use failed
        (so the env state at this point matches the pre-turn state).
        """
        first_error = next((err for (_, _, err) in parsed if err is not None), "unknown error")
        tool_results = []
        for tool_id, _actions, err in parsed:
            if err is not None:
                text = f"Tool input could not be parsed: {err}. No actions were executed this turn; please retry with a valid tool call."
            else:
                text = (
                    "Turn rolled back: a sibling tool_use in this same response failed "
                    f"to parse ({first_error}). No actions were executed; please retry "
                    "the intended sequence."
                )
            tool_results.append({
                "type": "tool_result",
                "content": [{"type": "text", "text": text}],
                "tool_use_id": tool_id,
                "is_error": True,
            })
        self.messages.append({"role": "user", "content": tool_results})

    # ---- Tool result construction ----

    def _get_screenshot_tool_content(self, action_output):
        """Generate tool content for explicit screenshot actions. Same resize
        as _obs_to_base64 to keep declared / sent resolutions in sync."""
        image = Image.open(action_output['output'])
        if image.size != (_SEND_W, _SEND_H):
            image = image.resize((_SEND_W, _SEND_H))
        buffered = BytesIO()
        image.save(buffered, format="PNG")
        encoded_string = base64.b64encode(buffered.getvalue()).decode()
        return {
            "type": "tool_result",
            "content": [
                {
                    "type": "text",
                    "text": "Here is the screenshot",
                },
                {
                    'type': 'image',
                    'source': {
                        'type': 'base64',
                        'media_type': 'image/png',
                        'data': encoded_string,
                    },
                }
            ],
            'tool_use_id': action_output['tool_id'],
            'is_error': False,
        }

    def _get_other_tool_content(self, action_output, screenshot_base64=None):
        """Generate tool content for non-screenshot actions, with screenshot feedback."""
        content = [
            {
                "type": "text",
                "text": "Executed the action. Here is the screenshot after the action.",
            },
        ]
        if screenshot_base64:
            content.append({
                'type': 'image',
                'source': {
                    'type': 'base64',
                    'media_type': 'image/png',
                    'data': screenshot_base64,
                },
            })
        return {
            "type": "tool_result",
            "content": content,
            'tool_use_id': action_output['tool_id'],
            'is_error': False,
        }

    def _get_tool_content_from_output(self, action_output, screenshot_base64=None):
        """Get tool content from action output based on action type."""
        if action_output['action'] == 'screenshot':
            return self._get_screenshot_tool_content(action_output)
        else:
            return self._get_other_tool_content(action_output, screenshot_base64=screenshot_base64)

    def _convert_action_outputs(self, action_outputs, fallback_b64=None):
        """Convert action outputs to tool_result content.

        Each action_output may carry its own post-action observation under the
        "obs" key (attached by run_single.py since v2). When present we encode
        that frame and attach it to the matching tool_result -- so every
        tool_use in a multi-tool turn gets the screenshot of *its* state,
        matching the official Anthropic computer-use loop's semantics.

        If "obs" is missing (older callers or future drivers), we fall back to
        the previous behaviour: attach `fallback_b64` (the post-final-action
        observation) to the last non-screenshot action_output of the turn and
        leave the earlier ones with text-only results. Screenshot actions
        always carry their own image via _get_screenshot_tool_content.
        """
        # Identify the last non-screenshot index for the fallback path.
        last_non_screenshot_idx = -1
        for i, ao in enumerate(action_outputs):
            if ao.get('action') != 'screenshot':
                last_non_screenshot_idx = i

        # Cache per-frame base64 so two identical paths in one turn aren't
        # re-encoded. Cheap insurance; usually a no-op.
        b64_cache: dict[str, str] = {}

        def encode_obs(ao_obs):
            if not ao_obs:
                return None
            path = (ao_obs.get('screen') or {}).get('path')
            if not path:
                return None
            cached = b64_cache.get(path)
            if cached is not None:
                return cached
            image = Image.open(path)
            if image.size != (_SEND_W, _SEND_H):
                image = image.resize((_SEND_W, _SEND_H))
            buffered = BytesIO()
            image.save(buffered, format="PNG")
            encoded = base64.b64encode(buffered.getvalue()).decode()
            b64_cache[path] = encoded
            return encoded

        tool_call_content = []
        for i, action_output in enumerate(action_outputs):
            if action_output.get('action') == 'screenshot':
                # _get_screenshot_tool_content reads action_output['output']
                # (path) and embeds the image itself.
                attach = None
            else:
                # Prefer the per-action obs attached by run_single.
                per_action_b64 = encode_obs(action_output.get('obs'))
                if per_action_b64 is not None:
                    attach = per_action_b64
                else:
                    # Legacy fallback: attach the post-final-action frame
                    # only to the last non-screenshot result of the turn.
                    attach = fallback_b64 if i == last_non_screenshot_idx else None

            tool_content = self._get_tool_content_from_output(
                action_output, screenshot_base64=attach
            )
            tool_call_content.append(tool_content)
        return tool_call_content
