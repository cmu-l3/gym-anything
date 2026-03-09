#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Research Archive Workflow Task Setup ==="
echo "Task: Create multi-format research archive (bookmark + reading list + PDF)"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install PDF processing libraries for verification
pip3 install -q PyPDF2 pypdf pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the research article HTML file
echo "Creating research article HTML..."
ARTICLE_DIR="/home/ga/Documents"
mkdir -p "$ARTICLE_DIR"

cat > "$ARTICLE_DIR/ai_agents_research.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Autonomous AI Agents: A Comprehensive Research Review</title>
    <style>
        body {
            font-family: 'Georgia', serif;
            line-height: 1.8;
            margin: 40px auto;
            max-width: 900px;
            padding: 0 20px;
            background: #f9f9f9;
        }
        .content {
            background: white;
            padding: 40px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        h1 {
            color: #1a1a1a;
            font-size: 2.2em;
            margin-bottom: 10px;
            border-bottom: 3px solid #0066cc;
            padding-bottom: 15px;
        }
        h2 {
            color: #333;
            font-size: 1.6em;
            margin-top: 30px;
            margin-bottom: 15px;
        }
        h3 {
            color: #555;
            font-size: 1.3em;
            margin-top: 25px;
        }
        p {
            margin: 15px 0;
            text-align: justify;
            color: #333;
        }
        .author {
            color: #666;
            font-style: italic;
            margin-bottom: 30px;
        }
        .abstract {
            background: #f0f7ff;
            border-left: 4px solid #0066cc;
            padding: 20px;
            margin: 20px 0;
            font-style: italic;
        }
        .keywords {
            background: #fff8e1;
            padding: 15px;
            margin: 20px 0;
            border-radius: 5px;
        }
        .highlight {
            background: #fffacd;
            padding: 2px 5px;
        }
        ul, ol {
            margin: 15px 0;
            padding-left: 30px;
        }
        li {
            margin: 8px 0;
        }
    </style>
</head>
<body>
    <div class="content">
        <h1>Autonomous AI Agents: A Comprehensive Research Review</h1>
        <p class="author">Research Article · AI Systems Laboratory · 2024</p>
        
        <div class="abstract">
            <strong>Abstract:</strong> This comprehensive review examines the current state of autonomous AI agents, 
            focusing on their architecture, learning mechanisms, and real-world applications. We analyze recent 
            advances in agent-based systems, including computer-use agents, web navigation agents, and multi-modal 
            reasoning systems. Our findings suggest that while significant progress has been made in specialized 
            domains, general-purpose autonomous agents remain an open challenge requiring innovations in reasoning, 
            planning, and learning from interaction.
        </div>

        <div class="keywords">
            <strong>Keywords:</strong> Autonomous Agents, Reinforcement Learning, Computer Use, AI Systems, 
            Multi-Agent Coordination, Vision-Language Models, Tool Use
        </div>

        <h2>1. Introduction</h2>
        
        <p>Autonomous AI agents represent a fundamental paradigm shift in artificial intelligence, moving from 
        passive prediction systems to active entities capable of perceiving, reasoning, and acting in complex 
        environments. Recent breakthroughs in large language models (LLMs) and vision-language models (VLMs) 
        have enabled unprecedented capabilities in agent systems, from navigating web interfaces to controlling 
        software applications autonomously.</p>

        <p>The field has witnessed explosive growth since 2022, with numerous research groups and companies 
        developing agent frameworks that combine language understanding, visual perception, and action execution. 
        These systems demonstrate emergent capabilities in task decomposition, tool use, and multi-step reasoning 
        that were previously unattainable.</p>

        <h2>2. Agent Architectures</h2>

        <h3>2.1 Perception-Action Loops</h3>
        <p>Modern agent architectures typically follow a <span class="highlight">perception-action loop</span> 
        where agents observe their environment, process observations through neural networks, select actions 
        based on learned policies, and receive feedback from the environment. This cycle enables continuous 
        learning and adaptation.</p>

        <p>Key architectural components include:</p>
        <ul>
            <li><strong>Observation Encoder:</strong> Transforms raw sensory input (screenshots, text, audio) 
            into structured representations</li>
            <li><strong>Memory System:</strong> Maintains short-term working memory and long-term episodic memory</li>
            <li><strong>Reasoning Module:</strong> Plans action sequences and evaluates potential outcomes</li>
            <li><strong>Action Executor:</strong> Translates high-level decisions into concrete API calls or 
            interface interactions</li>
        </ul>

        <h3>2.2 Language-Model-Based Agents</h3>
        <p>Large language models serve as the cognitive core of many modern agents. Systems like ReAct, 
        Reflexion, and AutoGPT demonstrate how LLMs can be prompted to generate reasoning traces, plan 
        action sequences, and reflect on execution outcomes. These agents leverage in-context learning to 
        adapt to new tasks without fine-tuning.</p>

        <h2>3. Learning Mechanisms</h2>

        <h3>3.1 Reinforcement Learning from Human Feedback (RLHF)</h3>
        <p>RLHF has emerged as a critical technique for aligning agent behavior with human preferences. 
        By training reward models on human-annotated trajectories, agents learn to optimize for outcomes 
        that humans find desirable, even when explicit reward functions are difficult to specify.</p>

        <h3>3.2 Self-Supervised Learning from Interaction</h3>
        <p>Recent work explores how agents can learn from their own experiences through techniques like:</p>
        <ol>
            <li>Hindsight Experience Replay (HER): Learning from failed attempts by relabeling goals</li>
            <li>Curiosity-driven exploration: Seeking novel states to expand knowledge</li>
            <li>Self-play: Improving through competition or collaboration with copies of themselves</li>
            <li>Question generation: Creating training tasks automatically to practice specific skills</li>
        </ol>

        <h3>3.3 Transfer Learning and Meta-Learning</h3>
        <p>Agents that can rapidly adapt to new environments and tasks represent a key frontier. 
        Meta-learning approaches train agents to "learn how to learn," enabling few-shot adaptation 
        to novel scenarios. Transfer learning leverages knowledge from related tasks to bootstrap 
        performance in new domains.</p>

        <h2>4. Computer-Use Agents</h2>

        <p>A particularly exciting application area is <span class="highlight">computer-use agents</span> 
        that can interact with graphical user interfaces, operating systems, and software applications. 
        These agents must master complex skills including:</p>

        <ul>
            <li>Visual grounding: Identifying UI elements from pixel observations</li>
            <li>Action planning: Decomposing high-level goals into GUI interactions</li>
            <li>State tracking: Maintaining awareness of application state across multiple screens</li>
            <li>Error recovery: Detecting and correcting mistakes in execution</li>
        </ul>

        <p>Benchmarks like OSWorld, WebArena, and Mind2Web provide standardized evaluation environments 
        for measuring progress in this domain. Current state-of-the-art agents achieve 20-40% success 
        rates on complex, multi-step tasks, indicating substantial room for improvement.</p>

        <h2>5. Challenges and Open Problems</h2>

        <h3>5.1 Robustness and Reliability</h3>
        <p>Agent systems often exhibit brittle behavior, failing catastrophically when encountering 
        slightly out-of-distribution scenarios. Improving robustness requires advances in:</p>
        <ul>
            <li>Uncertainty quantification: Knowing when the agent doesn't know</li>
            <li>Graceful degradation: Falling back to safer behaviors under uncertainty</li>
            <li>Human-in-the-loop oversight: Requesting help when confidence is low</li>
        </ul>

        <h3>5.2 Sample Efficiency</h3>
        <p>Current agents typically require millions of environment interactions to master even 
        moderately complex tasks. Improving sample efficiency through better priors, meta-learning, 
        and curriculum design remains a critical challenge.</p>

        <h3>5.3 Long-Horizon Planning</h3>
        <p>Decomposing goals into coherent multi-step plans and maintaining focus over extended 
        time horizons poses significant difficulties. Hierarchical reinforcement learning and 
        options frameworks offer promising directions but have yet to scale to complex real-world tasks.</p>

        <h3>5.4 Verification and Safety</h3>
        <p>As agents become more capable, ensuring they behave safely and as intended grows increasingly 
        important. Open challenges include:</p>
        <ul>
            <li>Specifying correct behavior for ambiguous tasks</li>
            <li>Detecting distribution shift and adversarial inputs</li>
            <li>Preventing harmful actions through learned or hard-coded constraints</li>
            <li>Maintaining interpretability as systems grow more complex</li>
        </ul>

        <h2>6. Applications and Impact</h2>

        <h3>6.1 Personal Productivity</h3>
        <p>AI agents are beginning to automate routine computer tasks like email management, calendar 
        scheduling, and data entry, potentially saving millions of hours of human labor.</p>

        <h3>6.2 Scientific Research</h3>
        <p>Agents that can autonomously run experiments, analyze data, and explore hypothesis spaces 
        could dramatically accelerate scientific discovery in fields from drug development to materials 
        science.</p>

        <h3>6.3 Software Development</h3>
        <p>Code-generating agents and AI pair programmers are transforming software engineering, 
        with systems like GitHub Copilot and GPT-4 demonstrating impressive capabilities in code 
        completion, bug fixing, and test generation.</p>

        <h3>6.4 Customer Service and Support</h3>
        <p>Conversational agents handling customer inquiries, troubleshooting technical issues, and 
        processing transactions are becoming increasingly sophisticated and widely deployed.</p>

        <h2>7. Future Directions</h2>

        <p>Looking ahead, several research directions appear particularly promising:</p>

        <ol>
            <li><strong>Multimodal Integration:</strong> Seamlessly combining vision, language, audio, 
            and other modalities for richer world understanding</li>
            <li><strong>Continual Learning:</strong> Agents that learn continuously from experience 
            without catastrophic forgetting</li>
            <li><strong>Collaborative Multi-Agent Systems:</strong> Teams of specialized agents 
            coordinating to solve complex tasks</li>
            <li><strong>Embodied Intelligence:</strong> Extending agent capabilities to physical 
            robots and embodied systems</li>
            <li><strong>Causal Reasoning:</strong> Moving beyond correlational pattern matching to 
            understanding causal mechanisms</li>
        </ol>

        <h2>8. Ethical Considerations</h2>

        <p>The development of increasingly autonomous AI systems raises important ethical questions:</p>

        <ul>
            <li><strong>Accountability:</strong> Who is responsible when an autonomous agent makes 
            a harmful decision?</li>
            <li><strong>Transparency:</strong> How can we ensure agents' decision-making processes 
            are interpretable and auditable?</li>
            <li><strong>Fairness:</strong> How do we prevent agents from perpetuating or amplifying 
            societal biases?</li>
            <li><strong>Privacy:</strong> What safeguards are needed when agents have access to 
            sensitive personal or organizational data?</li>
            <li><strong>Autonomy and Control:</strong> At what point do human oversight and approval 
            become necessary?</li>
        </ul>

        <h2>9. Conclusion</h2>

        <p>Autonomous AI agents represent one of the most exciting and rapidly advancing areas of 
        artificial intelligence research. While significant progress has been made in recent years, 
        substantial challenges remain before we achieve truly general-purpose agents capable of 
        matching human-level performance across diverse tasks.</p>

        <p>The path forward will require continued innovation in learning algorithms, architecture 
        design, evaluation methodologies, and safety frameworks. Interdisciplinary collaboration 
        between AI researchers, domain experts, ethicists, and policymakers will be essential to 
        realize the transformative potential of agent systems while mitigating risks.</p>

        <p>As we stand at this pivotal moment in AI development, the decisions we make today about 
        how to design, deploy, and govern autonomous agents will shape the technological landscape 
        for decades to come.</p>

        <h2>References</h2>
        <ol>
            <li>Yao, S. et al. (2023). "ReAct: Synergizing Reasoning and Acting in Language Models"</li>
            <li>Shinn, N. et al. (2023). "Reflexion: Language Agents with Verbal Reinforcement Learning"</li>
            <li>Xie, T. et al. (2024). "OSWorld: Benchmarking Multimodal Agents for Open-Ended Tasks"</li>
            <li>Zhou, S. et al. (2023). "WebArena: A Realistic Web Environment for Building Autonomous Agents"</li>
            <li>Deng, X. et al. (2023). "Mind2Web: Towards a Generalist Agent for the Web"</li>
        </ol>

        <p style="margin-top: 40px; padding-top: 20px; border-top: 2px solid #ddd; color: #666; font-size: 0.9em;">
            <em>This article provides a comprehensive overview of autonomous AI agents as of 2024. 
            For the latest developments in this rapidly evolving field, readers are encouraged to 
            consult recent conference proceedings (NeurIPS, ICML, ICLR) and preprint archives (arXiv).</em>
        </p>
    </div>
</body>
</html>
EOF

chown ga:ga "$ARTICLE_DIR/ai_agents_research.html"
echo "✓ Research article created at: $ARTICLE_DIR/ai_agents_research.html"

# Ensure Downloads directory exists and is clean
DOWNLOADS_DIR="/home/ga/Downloads"
mkdir -p "$DOWNLOADS_DIR"
chown ga:ga "$DOWNLOADS_DIR"

# Clear any existing PDFs to avoid false positives
echo "Cleaning Downloads directory..."
find "$DOWNLOADS_DIR" -name "*.pdf" -mmin -60 -delete 2>/dev/null || true

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to the research article
ARTICLE_URL="file:///home/ga/Documents/ai_agents_research.html"
echo "Navigating to: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$ARTICLE_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the AI agents research article"
echo ""
echo "Agent should now:"
echo "  1. Create a bookmark folder (e.g., 'AI Research 2024' or 'Research Papers')"
echo "  2. Bookmark this article in that folder with a descriptive name"
echo "  3. Add the article to Chrome's Reading List"
echo "  4. Save the article as PDF (Ctrl+P, Save as PDF)"
echo "  5. Name the PDF descriptively (e.g., 'ai_agents_research_review.pdf')"
echo ""
echo "This multi-format archival workflow ensures the content is preserved and organized."