from agents.agents.base import BaseAgent
from agents.shared.llm_clients import call_gemini_with_retry, parse_qwen3vl_response
from agents.shared.prompts import GEMINI_SYSTEM_PROMPT_SINGLE_STEP, TOOL_DEFINITIONS
from agents.agents.claude import ClaudeAgent
from PIL import Image
import json
import os
from io import BytesIO
import base64
import numpy as np


# python -m agents.evaluation.run_single --env_dir benchmarks/cua_world/environments/gimp_env_all_fast --task saturation_increase --agent 'ClaudeDatabricksAgent' --agent_args "{\"model\":\"databricks/claude-4-5-sonnet\", \"exp_name\":\"claude-4-5-sonnet\", \"task_name\": \"saturation_increase\"}"

class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.bool_):
            return bool(obj)
        # Let the base class default method raise the TypeError for other unhandled types
        return json.JSONEncoder.default(self, obj)


class Gemini3Agent(ClaudeAgent):
    """
    Claude Databricks agent using Claude Databricks models via OpenAI-compatible API.
    Maintains a history-based prompting approach with image preprocessing.
    """
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.system_prompt = GEMINI_SYSTEM_PROMPT_SINGLE_STEP
        self.system_prompt = self.system_prompt.replace('<<TOOL_DEFINITIONS>>', json.dumps(TOOL_DEFINITIONS))

    def process_image(self, image_path, resize_to = None):
        """
        Process an image for Qwen VL models with smart resize.
        Returns base64 encoded processed image.
        """
        image = Image.open(image_path)
        width, height = image.size
        
        if self.verbose:
            print(f"Original screen resolution: {width}x{height}")
        
        if resize_to is not None:
            image = image.resize((resize_to[0], resize_to[1]))
                
        # Convert to base64
        buffer = BytesIO()
        image.save(buffer, format="PNG")
        processed_bytes = buffer.getvalue()
        
        return base64.b64encode(processed_bytes).decode("utf-8")


    def step(self, obs, action_outputs):
        """
        Execute one agent step.
        
        Args:
            obs: Current observation from environment
            action_outputs: List of outputs from previous actions (not used for Qwen3VL agent)
        
        Returns:
            List of action groups to execute
        """
        # Save current observation
        self.save_observation(obs)
        self.step_idx += 1
        
        if self.messages[0]['role']!='system':
            self.messages.insert(0, {"role": "system", "content": self.system_prompt})
        # Process image
        processed_image_b64 = self.process_image(obs['screen']['path'], resize_to = (1920, 1080))
        
        # Build messages
        self.messages.append({"content": [{
            "type": "image_url",
            "image_url": {
                "url": f"data:image/png;base64,{processed_image_b64}"
            }
        }], "role": "user"})

        self.messages[-1]['cache_control'] = {"type": "ephemeral"}

        # Save messages for debugging
        # self.save_messages(self.messages)
        # Call LLM
        # print(f"Calling LLM with temperature: {self.temperature}")
        response = call_gemini_with_retry(
            self.messages, 
            self.model, 
            1.0, 
            0.95,
            20,
            reasoning_effort='low',
            return_full_response=True
        )
        self.messages.append({'role': 'assistant', 'content': response})
        try:
            reasoning_content = response.choices[0].message.reasoning_content
        except Exception as e:
            print(f"Error getting reasoning content: {e}")
            reasoning_content = None

        if reasoning_content is not None:
            response = '<think>' + reasoning_content + '</think>\n' + response.choices[0].message.content
        else:
            response = response.choices[0].message.content

        
        
        # Store response for history
        
        # Parse response using existing parse_owl_response function
        # Handle: multiple tool calls in a single response.
        parsed_response = parse_qwen3vl_response(response, scale_dims = True, scale_dims_ratio = (1920/1000, 1080/1000))
        
        # Store responses for later dumping
        # self.all_model_responses.append(response)
        # self.all_parsed_responses.append(parsed_response)
        
        # Extract actions and metadata
        actions = parsed_response['actions']
        metadata = parsed_response['metadata']
        
        # Update history with conclusion
        # self.history.append(metadata['conclusion'])
        
        if self.verbose:
            print(f"Step {self.step_idx + 1}:")
            print(f"  Thought: {metadata['thought']}")
            print(f"  Conclusion: {metadata['conclusion']}")
            print(f"  Action Type: {metadata['action_type']}")
            print(f"  Actions: {actions}")
        
        # Check if terminal
        if metadata['is_terminal']:
            self.done = True
            return [{
                'tool_id': f'qwen3vl_step_{self.step_idx}',
                'actions': actions,  # Empty list from parse_owl_response
                'metadata': metadata
            }]
        
        # Check if wait action
        if metadata['wait_time'] is not None:
            return [{
                'tool_id': f'qwen3vl_step_{self.step_idx}',
                'actions': [{'action': 'wait', 'time': metadata['wait_time']}],
                'metadata': metadata
            }]
        
        # Regular actions (mouse, keyboard, etc.)
        return [{
            'tool_id': f'qwen3vl_step_{self.step_idx}',
            'actions': actions,
            'metadata': metadata
        }]
