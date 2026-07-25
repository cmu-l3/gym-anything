"""GPT-5.4 Computer Use agent.

Uses the OpenAI Responses API with the native ``computer`` tool so GPT-5.4
(or GPT-5.5) can directly observe screenshots, reason about the GUI, and
emit mouse / keyboard actions.

Reference: https://developers.openai.com/api/docs/guides/tools-computer-use

Protocol notes:
- The tool is declared as ``{"type": "computer"}`` with no parameters; the
  model works in absolute pixel coordinates of the screenshots it receives,
  which this harness sends at native resolution (no scaling step).
- One ``computer_call`` carries a BATCH of actions. We split the batch into
  one action group per action so the GUI gets time to react between them.
- Conversation state lives server-side via ``previous_response_id``; each
  turn sends only the new ``computer_call_output`` (screenshot). Server-side
  compaction is enabled through ``compaction_threshold`` (default 64k
  rendered tokens).
- Mouse actions may carry a ``keys`` array of held modifiers (e.g.
  shift-click); we wrap the mouse primitives in keys_down/keys_up.
- The model often opens a turn with a bare screenshot request; we satisfy it
  from the already-captured frame instead of bouncing through an env step.
"""

from agents.agents.base import BaseAgent
from agents.shared.llm_clients import call_gpt54_computer_use, convert_gpt_key
from PIL import Image
import base64
import json
import os
import pickle
from io import BytesIO
from openai import OpenAI


class GPT54ComputerUseAgent(BaseAgent):
    """GPT-5.4 Computer Use agent using the OpenAI Responses API."""

    # ------------------------------------------------------------------ init
    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get('agent_args', {})
        self.model = self.agent_args.get('model', 'gpt-5.4')
        self.compaction_threshold = self.agent_args.get(
            'compaction_threshold', 64000
        )
        if self.compaction_threshold is not None:
            self.compaction_threshold = int(self.compaction_threshold)

        self.exp_name = self.agent_args.get('exp_name', 'exp')
        self.setup_custom_logger()

        self.client = OpenAI(
            api_key=self.agent_args.get('api_key', os.getenv("OPENAI_API_KEY")),
            base_url=self.agent_args.get('base_url'),
        )

        # Agent state
        self.done = False
        self.step_idx = -1
        self.previous_response_id = None
        self.last_computer_call = None   # most-recent computer_call item

        # Trajectory / artifact storage
        self.responses_metadata = []
        self.action_history = []

        self.debug = kwargs.get('debug', False)
        self.verbose = kwargs.get('verbose', False)

    def setup_custom_logger(self):
        task_name = self.agent_args.get('task_name', 'task')
        self.save_folder_custom = (
            f'all_runs/{self.exp_name}/{self.model}/{task_name}'
        )
        for run_number in range(0, 1000):
            candidate = f'{self.save_folder_custom}/run_{run_number}'
            if not os.path.exists(candidate):
                self.save_folder_custom = candidate
                break
        os.makedirs(self.save_folder_custom, exist_ok=False)

    def save_observation(self, observation):
        Image.open(observation['screen']['path']).save(
            f'{self.save_folder_custom}/observation_{self.step_idx}.png'
        )

    # ----------------------------------------------------------- agent init
    def init(self, task_description, display_resolution, save_path):
        self.task_description = task_description
        self.display_resolution = display_resolution
        self.save_path = save_path

    # -------------------------------------------------------- internal helpers

    def _get_screenshot_b64(self, obs):
        """Return the current observation screenshot as a base-64 PNG."""
        image = Image.open(obs['screen']['path'])
        buffered = BytesIO()
        image.save(buffered, format="PNG")
        return base64.b64encode(buffered.getvalue()).decode("utf-8")

    def _get_computer_call(self, response):
        """Return the first ``computer_call`` item in *response*, or None."""
        for item in response.output:
            if item.type == "computer_call":
                return item
        return None

    def _is_screenshot_only(self, actions):
        """True when every action in the batch is a screenshot request."""
        return len(actions) > 0 and all(a.type == "screenshot" for a in actions)

    def _send_screenshot(self, screenshot_b64):
        """Send a ``computer_call_output`` screenshot back to the model."""
        output_item = {
            "type": "computer_call_output",
            "call_id": self.last_computer_call.call_id,
            "output": {
                "type": "computer_screenshot",
                "image_url": f"data:image/png;base64,{screenshot_b64}",
                # Docs: "prefer detail: 'original' on screenshot inputs" —
                # preserves full resolution and improves click accuracy.
                "detail": "original",
            },
        }

        # Acknowledge pending safety checks when the API returns them
        pending = getattr(self.last_computer_call,
                          'pending_safety_checks', None)
        if pending:
            output_item["acknowledged_safety_checks"] = [
                check.id for check in pending
            ]

        response = call_gpt54_computer_use(
            self.client,
            self.model,
            [{"type": "computer"}],
            [output_item],
            previous_response_id=self.previous_response_id,
            compaction_threshold=self.compaction_threshold,
        )
        self.previous_response_id = response.id
        self._record_response_metadata(response)
        return response

    def _record_response_metadata(self, response):
        """Persist lightweight metadata about every API response."""
        meta = {
            'id': response.id,
            'output_types': [item.type for item in response.output],
        }
        for item in response.output:
            if hasattr(item, 'content') and item.content:
                for part in item.content:
                    if hasattr(part, 'text'):
                        meta['text_output'] = part.text
                        break
            # Capture reasoning summary when available
            if item.type == 'reasoning' and hasattr(item, 'summary'):
                summaries = item.summary
                if isinstance(summaries, list):
                    meta['thinking'] = '\n'.join(
                        s.text for s in summaries if hasattr(s, 'text')
                    )
                elif isinstance(summaries, str):
                    meta['thinking'] = summaries
        self.responses_metadata.append(meta)

    # ------------------------------------------------------ action serialization

    def _serialize_action(self, action):
        """Serialize a GPT action object to a JSON-friendly dict with full details."""
        atype = action.type
        info = {'type': atype}

        if atype in ("click", "double_click", "triple_click", "move"):
            info['x'] = int(action.x)
            info['y'] = int(action.y)
            if atype == "click":
                info['button'] = getattr(action, 'button', 'left')
        elif atype == "scroll":
            info['x'] = int(action.x)
            info['y'] = int(action.y)
            info['scrollX'] = getattr(action, 'scrollX', 0)
            info['scrollY'] = getattr(action, 'scrollY', 0)
        elif atype == "keypress":
            info['keys'] = list(action.keys)
        elif atype == "type":
            info['text'] = action.text
        elif atype == "drag":
            if hasattr(action, 'path') and action.path:
                info['path'] = [[int(p.x), int(p.y)] for p in action.path]
        elif atype == "wait":
            info['time'] = getattr(action, 'time', 2.0)

        held = getattr(action, 'keys', None)
        if held and atype != "keypress":
            info['held_keys'] = list(held)

        return info

    # ------------------------------------------------------ action conversion

    @staticmethod
    def _held_modifiers(action):
        """Modifier keys held for the duration of a mouse action (docs: the
        mouse action's optional ``keys`` array), mapped to env names."""
        held = getattr(action, 'keys', None)
        if not held:
            return []
        return [convert_gpt_key(k) for k in held]

    def _convert_single_action(self, action):
        """Convert one GPT action object to a list of gym primitives."""
        atype = action.type

        if atype == "click":
            x, y = int(action.x), int(action.y)
            button = getattr(action, 'button', 'left')
            if button == 'right':
                primitives = [{'mouse': {'right_click': [x, y]}}]
            elif button == 'middle':
                primitives = [{'mouse': {'middle_click': [x, y]}}]
            else:
                primitives = [{'mouse': {'left_click': [x, y]}}]

        elif atype == "double_click":
            x, y = int(action.x), int(action.y)
            primitives = [{'mouse': {'double_click': [x, y]}}]

        elif atype == "triple_click":
            x, y = int(action.x), int(action.y)
            primitives = [{'mouse': {'triple_click': [x, y]}}]

        elif atype == "scroll":
            x, y = int(action.x), int(action.y)
            scroll_x = getattr(action, 'scrollX', 0)
            scroll_y = getattr(action, 'scrollY', 0)
            primitives = [{'mouse': {'move': [x, y]}}]
            if scroll_x:
                # Runner doesn't support hscroll natively; warn
                print(f"[GPT54CU] Warning: horizontal scroll "
                      f"(scrollX={scroll_x}) not supported, ignoring")
            if scroll_y:
                primitives.append({'mouse': {'scroll': scroll_y}})

        elif atype == "keypress":
            keys = [convert_gpt_key(k) for k in action.keys]
            return [{'keyboard': {'keys': keys}}]

        elif atype == "type":
            return [{'keyboard': {'text': action.text}}]

        elif atype == "drag":
            if hasattr(action, 'path') and action.path:
                points = [(int(p.x), int(p.y)) for p in action.path]
            else:
                sx = int(getattr(action, 'startX',
                                 getattr(action, 'x', 0)))
                sy = int(getattr(action, 'startY',
                                 getattr(action, 'y', 0)))
                ex = int(getattr(action, 'endX', sx))
                ey = int(getattr(action, 'endY', sy))
                points = [(sx, sy), (ex, ey)]
            primitives = [
                {'mouse': {'move': list(points[0])}},
                {'mouse': {'buttons': {'left_down': True}}},
            ]
            for pt in points[1:]:
                primitives.append({'mouse': {'move': list(pt)}})
            primitives.append({'mouse': {'buttons': {'left_up': True}}})

        elif atype == "move":
            x, y = int(action.x), int(action.y)
            primitives = [{'mouse': {'move': [x, y]}}]

        else:
            # wait / screenshot → handled at the group level
            return []

        held = self._held_modifiers(action)
        if held:
            primitives = (
                [{'keyboard': {'keys_down': held}}]
                + primitives
                + [{'keyboard': {'keys_up': held}}]
            )
        return primitives

    def _build_action_groups(self, actions, call_id):
        """
        Split a GPT ``computer_call`` action batch into separate action
        groups that the eval loop can execute one at a time.

        GPT often batches actions like ``[keypress, keypress, wait]``.
        If we send them all as a single ``env.step()`` call the GUI has
        no time to react (e.g. a menu must open before the next key).

        Strategy: emit **one action group per GPT action**.  Each group
        goes through the loop's action processing individually, giving
        the environment time to update between them.  ``wait`` actions
        become their own group so the loop sleeps properly.
        """
        groups = []
        for idx, action in enumerate(actions):
            atype = action.type

            if atype == "screenshot":
                # no-op inside a batch; the loop captures a frame anyway
                continue

            if atype == "wait":
                wait_time = getattr(action, 'time', 2.0)
                groups.append({
                    'tool_id': f'{call_id}_w{idx}',
                    'actions': [{'action': 'wait', 'time': wait_time}],
                })
                continue

            gym_primitives = self._convert_single_action(action)
            if gym_primitives:
                groups.append({
                    'tool_id': f'{call_id}_{idx}',
                    'actions': gym_primitives,
                })

        return groups

    # ----------------------------------------------------------------- step

    def step(self, obs, action_outputs):
        self.step_idx += 1
        self.save_observation(obs)

        screenshot_b64 = self._get_screenshot_b64(obs)

        # ── first turn: send the task description ──
        if self.step_idx == 0:
            response = call_gpt54_computer_use(
                self.client,
                self.model,
                [{"type": "computer"}],
                self.task_description,
                compaction_threshold=self.compaction_threshold,
            )
            self.previous_response_id = response.id
            self._record_response_metadata(response)
        else:
            # ── subsequent turns: return the latest screenshot ──
            response = self._send_screenshot(screenshot_b64)

        # ── resolve internal screenshot-only loops ──
        # The model often opens with a bare "screenshot" request.  We satisfy
        # it immediately (we already have the frame) instead of bouncing back
        # to the outer loop for a redundant capture.
        max_internal = 20
        for _ in range(max_internal):
            computer_call = self._get_computer_call(response)

            if computer_call is None:
                # No computer_call → model considers the task complete
                self.done = True
                if self.verbose:
                    for item in response.output:
                        if hasattr(item, 'content'):
                            print(f"[GPT54CU] Final: {item.content}")
                return []

            self.last_computer_call = computer_call

            if self._is_screenshot_only(computer_call.actions):
                if self.verbose:
                    print("[GPT54CU] Internal screenshot request – "
                          "replying with current frame")
                response = self._send_screenshot(screenshot_b64)
                continue

            # Got real GUI actions → break out
            break
        else:
            print(f"[GPT54CU] Warning: exceeded {max_internal} internal "
                  "screenshot loops – marking done")
            self.done = True
            return []

        # ── split into per-action groups so the loop executes them one
        #    at a time, giving the GUI time to react between actions ──
        action_groups = self._build_action_groups(
            computer_call.actions, computer_call.call_id)

        if self.verbose:
            gpt_types = [a.type for a in computer_call.actions]
            print(f"[GPT54CU] Step {self.step_idx}: "
                  f"{gpt_types} -> {len(action_groups)} action groups")

        # Record history with full action details
        self.action_history.append({
            'step': self.step_idx,
            'call_id': computer_call.call_id,
            'gpt_actions': [self._serialize_action(a) for a in computer_call.actions],
        })

        if not action_groups:
            self.done = True
            return []
        return action_groups

    # --------------------------------------------------------------- finish

    def finish(self, *args, **kwargs):
        # Action history
        for dest in (self.save_path, self.save_folder_custom):
            try:
                with open(f'{dest}/action_history.json', 'w') as f:
                    json.dump(self.action_history, f, indent=4)
            except Exception as e:
                print(f"Error saving action_history to {dest}: {e}")

        # Response metadata
        for dest in (self.save_path, self.save_folder_custom):
            try:
                with open(f'{dest}/responses_metadata.json', 'w') as f:
                    json.dump(self.responses_metadata, f, indent=4)
            except Exception as e:
                print(f"Error saving responses_metadata to {dest}: {e}")

        # Info dict
        if 'info' in kwargs:
            info = kwargs['info']
            try:
                with open(
                    f'{self.save_folder_custom}/info.json', 'w'
                ) as f:
                    json.dump(info, f, indent=4)
            except Exception:
                with open(
                    f'{self.save_folder_custom}/info.pkl', 'wb'
                ) as f:
                    pickle.dump(info, f)
