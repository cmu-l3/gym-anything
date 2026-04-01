"""
This script is used to ask a Computer-Use Agent (CUA) questions related to gui interactions.
"""

from random import betavariate
import litellm

import sys
import argparse
from PIL import Image
import base64
from dotenv import load_dotenv
import os
from baselines.common.prompts import CLAUDE_SYSTEM_PROMPT
from anthropic import Anthropic
import uuid
import pickle
import openai
load_dotenv()

# litellm.api_key = os.getenv('GEMINI_API_KEY')

parser = argparse.ArgumentParser()
parser.add_argument('--question', type=str, required=True)
parser.add_argument('--screenshot_path', type=str, required=True)
parser.add_argument('--reasoning_effort', type=str, default='low', choices=['low', 'none', 'high'])
args = parser.parse_args()
question = args.question
screenshot_path = args.screenshot_path
img = Image.open(screenshot_path)

def encode_image(image_path):
    image = Image.open(image_path)
    image = image.resize((1280, 720))
    from io import BytesIO
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    return base64.b64encode(buffer.getvalue()).decode('utf-8')

messages = [
    {
        "role": "user",
        "content": 
        [
            {
                "type": "text",
                "text": question
            },
            {
                    'type': 'image_url',
                    'image_url': {
                        'url': f'data:image/png;base64,{encode_image(screenshot_path)}'
                    },
                    # 'source': {
                    #     'type': 'base64',
                    #     'media_type': 'image/png',
                    #     'data': encode_image(screenshot_path),
                    # },
                }
        ]
    }
]

client = openai.OpenAI(
    base_url=os.environ.get("DATABRICKS_BASE_URL", "https://YOUR_DATABRICKS_WORKSPACE.azuredatabricks.net/serving-endpoints"),
    api_key=os.environ.get("DATABRICKS_API_KEY", ""),
)


# response = client.beta.messages.create(
#     model='claude-haiku-4-5',
#     messages=messages,
#     system=CLAUDE_SYSTEM_PROMPT,
#     betas=["computer-use-2025-01-24"],
#     temperature=0.0,
#     max_tokens=4096,
# )
response = client.chat.completions.create(
    model='databricks-claude-sonnet-4-5',
    messages=[{'role': 'system', 'content': CLAUDE_SYSTEM_PROMPT}, *messages],
    # temperature=temperature,
    # top_p=top_p,
    # extra_body={"repetition_penalty": 1.0, "top_k": top_k},
    max_tokens=4096,
    extra_headers={"anthropic-beta": "beta_flag"},
    extra_body={
        "thinking": {
            "type": "enabled",
            "budget_tokens": 2048
        }
    }
)
try:
    os.makedirs('claude_usage_dumps_haiku', exist_ok=True)
    with open(f'claude_usage_dumps_haiku/{uuid.uuid4()}.pkl', 'wb') as f:
        pickle.dump(response, f)
except Exception as e:
    print(f"Error dumping response: {e}")

# response = response.content[0].text
response = response.choices[0].message.content[-1]['text']
print('Model Response: ', response, '\n\n'+f'IMPORTANT: If the response contains any coordinates (eg, for mouse clicks), they would have been normalized to 1280*720 display scale. Please convert them according to the actual display resolution (eg: {img.width}x{img.height}).')