from agents.agents.qwen3vl import Qwen3VLAgent
from agents.shared.llm_clients import call_llm, parse_qwen3vl_response
import json
import os
import copy
import numpy as np


class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.bool_):
            return bool(obj)
        return json.JSONEncoder.default(self, obj)


class Qwen3VLAuditAgent(Qwen3VLAgent):
    """
    Qwen3VL agent with self-audit capability for increased test-time compute.

    When the agent attempts to terminate, an audit phase runs using the SAME model
    to verify task completion. If the audit determines the task is incomplete,
    feedback is injected back into the main agent's context to continue working.

    This enables the agent to self-correct and retry before final termination.
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        # Audit configuration (from agent_args)
        self.audit_enabled = self.agent_args.get('audit_enabled', True)
        self.max_audits = self.agent_args.get('max_audits', 3)
        self.audit_image_interval = self.agent_args.get('audit_image_interval', 1)

        # Audit state
        self.audit_count = 0  # Number of FAILED audits (rejections)
        self.total_audits = 0  # Total number of audits performed
        self.last_audit_feedback = None
        self.audit_responses = []
        self.in_audit_recovery = False

        print(f"[Qwen3VLAuditAgent] Initialized with audit_enabled={self.audit_enabled}, max_audits={self.max_audits}")

    def get_audit_system_prompt(self):
        """Returns the system prompt for the audit agent."""
        return '''You are a helpful assistant that looks through trajectory of an agent interacting with a computer-use software, and identify whether the task was completed correctly or not. You will be provided with screenshots of the full trajectory. You will also be provided with task description that the agent was trying to solve.'''

    def build_audit_messages(self, current_screenshot_b64, image_interval=1):
        """
        Builds the message payload for the audit call.

        Uses the same prompting strategy as verify_all_tasks_gemini.py:
        - NO action history (to avoid bias from agent's self-reported reasoning)
        - Smart image sampling: first 3 + sampled middle + last 3
        - Focus on visual evidence only

        Args:
            current_screenshot_b64: The current/final screenshot
            image_interval: Sample every Nth screenshot for middle section (increases on retry if context overflow)

        Returns:
            List of messages for the audit LLM call
        """
        # Smart image sampling: first 3 + middle sampled + last 3
        # This ensures we see the initial state, key middle steps, and final state
        all_screenshots = self.screenshots.copy()

        # Ensure current screenshot is included
        if current_screenshot_b64 not in all_screenshots:
            all_screenshots.append(current_screenshot_b64)

        if len(all_screenshots) <= 6:
            # If 6 or fewer images, use all of them
            sampled_screenshots = all_screenshots
        else:
            # First 3 + middle sampled + last 3
            first_3 = all_screenshots[:3]
            last_3 = all_screenshots[-3:]
            middle = all_screenshots[3:-3]
            middle_sampled = middle[::image_interval] if len(middle) > 0 else []
            sampled_screenshots = first_3 + middle_sampled + last_3

        # Build image content list (NO action history - only visual evidence)
        image_content = []
        for img in sampled_screenshots:
            image_content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{img}"}
            })

        num_images = len(sampled_screenshots)

        messages = [
            {
                "role": "system",
                "content": self.get_audit_system_prompt()
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": f"Here is the task description: {self.task_description}"
                    }
                ]
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": f"Here are the screenshots of the full trajectory (note, images are provided every {image_interval} steps + first 3 and last 3 steps, total {num_images} images): "
                    }
                ] + image_content
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": f'''Based on the trajectory and task description: ```{self.task_description}```, identify whether original task correctly solved? Was there any points where the agent lied? Was environment used to solve task, or was the task completed using knowledge? Did the agent cheat at any point? Give your final answer in a json format, with keys: "solved": "true/false/partial", "reasoning": "<your_explanation>"'''
                    }
                ]
            }
        ]

        return messages

    def run_audit(self, current_screenshot_b64):
        """
        Executes the audit and parses the response.

        Uses adaptive image interval: starts at self.audit_image_interval,
        increases by 1 on each failure (e.g., context overflow) until success.

        Args:
            current_screenshot_b64: The current/final screenshot

        Returns:
            Dict with keys: task_complete, confidence, reasoning, missing_steps, feedback
        """
        self.total_audits += 1
        print(f"[AUDIT] Running audit #{self.total_audits} (failed so far: {self.audit_count}, max failures: {self.max_audits})")

        current_interval = self.audit_image_interval
        max_interval_attempts = 20  # Prevent infinite loop

        for attempt in range(max_interval_attempts):
            try:
                messages = self.build_audit_messages(current_screenshot_b64, image_interval=current_interval)

                # Save audit messages for debugging
                self._save_audit_messages(messages, current_interval)

                print(f"[AUDIT] Attempt {attempt + 1}: Using image_interval={current_interval}, ~{len(self.screenshots) // max(current_interval, 1) + 1} images")

                # Call same model for audit via call_llm (Qwen3VL backend)
                response = call_llm(
                    messages,
                    self.model,  # Same model as main agent
                    self.temperature,  # Same temperature as main agent
                    self.top_p,
                    self.top_k,
                )

                # Success - store and parse response
                self.audit_responses.append({
                    'response': response,
                    'image_interval': current_interval,
                    'attempt': attempt + 1
                })

                return self._parse_audit_response(response)

            except Exception as e:
                error_str = str(e).lower()
                print(f"[AUDIT] Attempt {attempt + 1} failed with interval={current_interval}: {e}")

                # Check if it's a context/token limit error
                if any(keyword in error_str for keyword in ['token', 'context', 'limit', 'too long', 'exceeded', '400', '413']):
                    current_interval += 1
                    print(f"[AUDIT] Increasing image_interval to {current_interval} and retrying...")
                    continue
                else:
                    # Some other error - still try increasing interval
                    current_interval += 1
                    if attempt < max_interval_attempts - 1:
                        continue
                    else:
                        # Give up and return conservative result
                        print(f"[AUDIT] All attempts failed. Returning 'not complete' as fallback.")
                        return {
                            "task_complete": False,
                            "solved": "false",
                            "reasoning": f"Audit failed after {attempt + 1} attempts: {e}",
                            "feedback": f"Audit system encountered errors. Please verify task completion manually and try again."
                        }

        # Should not reach here, but just in case
        return {
            "task_complete": False,
            "solved": "false",
            "reasoning": "Audit exhausted all retry attempts",
            "feedback": "Audit could not complete. Please continue working on the task."
        }

    def _parse_audit_response(self, response):
        """
        Parses the audit response, handling <think> tags and JSON extraction.

        Expected response format:
        {
            "solved": "true/false/partial",
            "reasoning": "<explanation>"
        }

        Args:
            response: Raw response string from the audit LLM call

        Returns:
            Dict with keys: task_complete, solved, reasoning, feedback
        """
        try:
            working_response = response

            # Handle thinking tags if present
            if '</think>' in working_response:
                working_response = working_response.split('</think>')[1]

            # Extract JSON from response
            json_str = None

            if '```json' in working_response:
                json_str = working_response.split('```json')[1].split('```')[0].strip()
            elif '```' in working_response:
                # Try generic code block
                json_str = working_response.split('```')[1].split('```')[0].strip()
            elif '{' in working_response:
                # Find JSON object directly
                start = working_response.find('{')
                end = working_response.rfind('}') + 1
                if start != -1 and end > start:
                    json_str = working_response[start:end]

            if json_str is None:
                raise ValueError("No JSON found in response")

            result = json.loads(json_str)

            # Handle the "solved" field
            solved_value = result.get('solved', 'false')
            if isinstance(solved_value, bool):
                task_complete = solved_value
            elif isinstance(solved_value, str):
                task_complete = solved_value.lower() == 'true'
            else:
                task_complete = False

            result['task_complete'] = task_complete
            result['solved'] = solved_value
            result.setdefault('reasoning', 'No reasoning provided')

            # Build feedback string for main agent
            if not task_complete:
                reasoning = result.get('reasoning', '')
                result['feedback'] = f"AUDIT FEEDBACK: {reasoning}"
            else:
                result['feedback'] = None

            print(f"[AUDIT] Parsed result: solved={solved_value}, task_complete={task_complete}")
            return result

        except Exception as e:
            print(f"[AUDIT] Parse error: {e}")
            print(f"[AUDIT] Raw response: {response[:500]}...")
            return {
                "task_complete": False,
                "solved": "false",
                "reasoning": f"Failed to parse audit response: {e}",
                "feedback": f"Audit response could not be parsed. Please verify the task is complete and try terminating again."
            }

    def _save_audit_messages(self, messages, image_interval):
        """Saves audit messages for debugging."""
        try:
            # Create a saveable version (truncate base64 for readability)
            saveable_messages = []
            for msg in messages:
                saveable_msg = {"role": msg["role"]}
                content = msg.get("content", [])
                if isinstance(content, str):
                    saveable_msg["content"] = content
                elif isinstance(content, list):
                    saveable_content = []
                    for item in content:
                        if isinstance(item, dict):
                            if item.get("type") == "image_url":
                                saveable_content.append({
                                    "type": "image_url",
                                    "image_url": {"url": item["image_url"]["url"][:100] + "...[truncated]"}
                                })
                            else:
                                saveable_content.append(item)
                    saveable_msg["content"] = saveable_content
                saveable_messages.append(saveable_msg)

            path = os.path.join(self.save_folder_custom, f"audit_messages_{self.audit_count}_interval_{image_interval}.json")
            with open(path, 'w') as f:
                json.dump(saveable_messages, f, indent=2)
        except Exception as e:
            print(f"[AUDIT] Failed to save audit messages: {e}")

    def build_messages(self, current_screenshot_b64):
        """
        Build the messages list for LLM call, including history if available.

        OVERRIDE: Injects audit feedback when recovering from a failed audit.
        """
        # Get base instruction prompt components from parent logic
        system_prompt = self.get_system_prompt()

        current_step = self.step_idx + 1
        history_start_idx = max(0, current_step - self.history_n)

        previous_actions = []
        for i in range(history_start_idx):
            previous_actions.append(f"Step {i+1}: {self.history[i]}")
        previous_actions_str = (
            "\n".join(previous_actions) if previous_actions else "None"
        )
        print('Len of previous actions: ', len(previous_actions))

        instruction_prompt = f"""Please generate the next move according to the UI screenshot, instruction and previous actions.

Instruction: {self.task_description}

Previous actions:
{previous_actions_str}"""

        # MODIFICATION: Inject audit feedback if recovering from failed audit
        if self.last_audit_feedback:
            feedback_injection = f"""

=== IMPORTANT: TASK VERIFICATION FAILED ===

Your previous attempt to mark the task as complete was reviewed and found INCOMPLETE.

{self.last_audit_feedback}

Please carefully address the issues mentioned above and continue working on the task.
Do NOT use the terminate action until you have fully addressed the feedback.

============================================
"""
            instruction_prompt = instruction_prompt + feedback_injection
            print(f"[AUDIT] Injected feedback into prompt")

            # Clear feedback after using it
            self.last_audit_feedback = None
            self.in_audit_recovery = True

        # Build messages (same logic as parent)
        messages = [
            {
                "role": "system",
                "content": [
                    {"type": "text", "text": system_prompt},
                ],
            }
        ]

        # Add conversation history if available
        history_len = min(self.history_n, len(self.responses))
        if history_len > 0:
            history_responses = self.responses[-history_len:]
            history_screenshots = self.screenshots[-history_len - 1:-1]

            for idx in range(history_len):
                if idx < len(history_screenshots):
                    screenshot_b64 = history_screenshots[idx]
                    if idx == 0:
                        img_url = f"data:image/png;base64,{screenshot_b64}"
                        messages.append({
                            "role": "user",
                            "content": [
                                {
                                    "type": "image_url",
                                    "image_url": {"url": img_url},
                                },
                                {"type": "text", "text": instruction_prompt},
                            ],
                        })
                    else:
                        img_url = f"data:image/png;base64,{screenshot_b64}"
                        messages.append({
                            "role": "user",
                            "content": [
                                {
                                    "type": "image_url",
                                    "image_url": {"url": img_url},
                                }
                            ],
                        })

                messages.append({
                    "role": "assistant",
                    "content": [
                        {"type": "text", "text": f"{history_responses[idx]}"},
                    ],
                })

            curr_img_url = f"data:image/png;base64,{current_screenshot_b64}"
            messages.append({
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": curr_img_url},
                    },
                ],
            })
        else:
            curr_img_url = f"data:image/png;base64,{current_screenshot_b64}"
            messages.append({
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": curr_img_url},
                    },
                    {"type": "text", "text": instruction_prompt},
                ],
            })

        return messages

    def step(self, obs, action_outputs):
        """
        Execute one agent step with audit-on-terminate logic.

        OVERRIDE: When agent attempts to terminate, runs audit first.
        If audit says task incomplete, injects feedback and continues.
        """
        self.step_idx += 1

        # Process image and save to disk (also saves as observation)
        processed_image_b64, processed_path = self.process_image(obs['screen']['path'])
        self.screenshots.append(processed_image_b64)

        # Store mapping for efficient message saving
        self.b64_to_path[processed_image_b64] = processed_path

        # Build messages (will include audit feedback if present)
        messages = self.build_messages(processed_image_b64)


        # Save messages with file paths instead of base64
        self.save_messages(messages)

        # Call LLM
        print(f"Calling LLM with temperature: {self.temperature}")
        response = call_llm(
            messages,
            self.model,
            self.temperature,
            self.top_p,
            self.top_k,
        )


        # Store response for history
        self.responses.append(response)

        # Parse response (no coordinate scaling - Qwen3VL uses native coordinates)
        parsed_response = parse_qwen3vl_response(response)


        self.all_model_responses.append(response)
        self.all_parsed_responses.append(parsed_response)

        # Extract actions and metadata
        actions = parsed_response['actions']
        metadata = parsed_response['metadata']

        # Update history with conclusion
        self.history.append(metadata['conclusion'])

        if self.verbose:
            print(f"Step {self.step_idx + 1}:")
            print(f"  Thought: {metadata['thought']}")
            print(f"  Conclusion: {metadata['conclusion']}")
            print(f"  Action Type: {metadata['action_type']}")
            print(f"  Actions: {actions}")

        # ═══════════════════════════════════════════════════════════════
        # AUDIT LOGIC: When agent wants to terminate
        # ═══════════════════════════════════════════════════════════════
        if metadata['is_terminal']:
            if not self.audit_enabled:
                # Audit disabled - normal terminate
                print(f"[AUDIT] Audit disabled, terminating normally")
                self.done = True
                return [{
                    'tool_id': f'qwen3vl_audit_step_{self.step_idx}',
                    'actions': actions,
                    'metadata': metadata
                }]

            # Run audit to verify task completion
            audit_result = self.run_audit(processed_image_b64)

            if audit_result.get('task_complete', False):
                # Audit confirmed task is complete
                print(f"[AUDIT] Task confirmed COMPLETE (solved: {audit_result.get('solved', 'unknown')}, total audits: {self.total_audits})")
                self.done = True
                metadata['audit_verified'] = True
                metadata['audit_solved'] = audit_result.get('solved', 'unknown')
                metadata['total_audits'] = self.total_audits
                metadata['failed_audits'] = self.audit_count
                return [{
                    'tool_id': f'qwen3vl_audit_step_{self.step_idx}',
                    'actions': actions,
                    'metadata': metadata
                }]
            else:
                # Audit says task is NOT complete
                self.audit_count += 1
                print(f"[AUDIT] Task NOT complete (total audits: {self.total_audits}, failed: {self.audit_count}/{self.max_audits})")
                print(f"[AUDIT] Reasoning: {audit_result.get('reasoning', 'N/A')[:200]}...")

                if self.audit_count >= self.max_audits:
                    # Force terminate after max audits
                    print(f"[AUDIT] Max failed audits ({self.max_audits}) reached. Force terminating.")
                    self.done = True
                    metadata['audit_force_terminated'] = True
                    metadata['total_audits'] = self.total_audits
                    metadata['failed_audits'] = self.audit_count
                    return [{
                        'tool_id': f'qwen3vl_audit_step_{self.step_idx}',
                        'actions': actions,
                        'metadata': metadata
                    }]

                # Store feedback for next step
                self.last_audit_feedback = audit_result.get('feedback', 'Task appears incomplete. Please continue working.')

                # Return wait action to continue (NOT terminate)
                # The next step() call will have the feedback injected
                return [{
                    'tool_id': f'qwen3vl_audit_step_{self.step_idx}_retry',
                    'actions': [{'action': 'wait', 'time': 1.0}],
                    'metadata': {
                        'thought': metadata.get('thought', ''),
                        'conclusion': f'Audit rejected termination (total: {self.total_audits}, failed: {self.audit_count}/{self.max_audits})',
                        'action_type': 'wait',
                        'is_terminal': False,
                        'wait_time': 1.0,
                        'audit_rejected': True,
                        'total_audits': self.total_audits,
                        'failed_audits': self.audit_count,
                        'audit_feedback_preview': audit_result.get('reasoning', '')[:100]
                    }
                }]

        # ═══════════════════════════════════════════════════════════════
        # Non-terminal actions - normal flow
        # ═══════════════════════════════════════════════════════════════
        if metadata['wait_time'] is not None:
            return [{
                'tool_id': f'qwen3vl_audit_step_{self.step_idx}',
                'actions': [{'action': 'wait', 'time': metadata['wait_time']}],
                'metadata': metadata
            }]

        return [{
            'tool_id': f'qwen3vl_audit_step_{self.step_idx}',
            'actions': actions,
            'metadata': metadata
        }]

    def finish(self, *args, **kwargs):
        """Save all agent artifacts including audit-specific data."""
        # Call parent finish
        super().finish(*args, **kwargs)

        # Save audit-specific data
        audit_data = {
            'audit_enabled': self.audit_enabled,
            'total_audits': self.total_audits,  # Total audits performed
            'audit_count': self.audit_count,  # Failed audits (rejections)
            'max_audits': self.max_audits,
            'audit_image_interval': self.audit_image_interval,
            'audit_responses': self.audit_responses,
            'in_audit_recovery': self.in_audit_recovery
        }

        try:
            with open(f'{self.save_folder_custom}/audit_data.json', 'w') as f:
                json.dump(audit_data, f, indent=4, cls=CustomJSONEncoder)
        except Exception as e:
            print(f"[AUDIT] Failed to save audit data: {e}")

        try:
            with open(f'{self.save_path}/audit_data.json', 'w') as f:
                json.dump(audit_data, f, indent=4, cls=CustomJSONEncoder)
        except Exception as e:
            print(f"[AUDIT] Failed to save audit data to save_path: {e}")
