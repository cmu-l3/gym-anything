"""
Simple Flask-based Trajectory Viewer

A lightweight web interface for viewing AI agent trajectories.
No complex state management - just clean HTML/JS.
"""

from flask import Flask, render_template, jsonify, send_file, request
from pathlib import Path
import json
from trajectory_utils import (
    get_all_runs,
    load_messages,
    load_info,
    extract_trajectory_steps,
    format_tool_call,
    get_run_summary,
    compute_experiment_statistics,
    compare_experiments,
    # Owl-specific functions
    load_owl_info,
    load_owl_parsed_responses,
    extract_owl_trajectory_steps,
    is_owl_run,
    # GPT-5.4-specific functions
    is_gpt54_run,
    extract_gpt54_trajectory_steps,
    # Delta compression support
    has_delta_compression,
    get_delta_frame_as_png,
    get_delta_step_numbers
)
import sys

app = Flask(__name__)

# Global storage for runs
ALL_RUNS = []


def init_runs(constraint : str = None):
    """Initialize the runs database."""
    global ALL_RUNS
    print("Loading runs...")
    ALL_RUNS = get_all_runs('all_runs', constraint)
    print(f"Found {len(ALL_RUNS)} runs")


@app.route('/')
def index():
    """Main page."""
    return render_template('index.html')


@app.route('/api/runs')
def api_runs():
    """Get all available runs."""
    # Group by experiment, model, task
    runs_data = {
        'experiments': sorted(list(set(r['experiment'] for r in ALL_RUNS))),
        'runs': ALL_RUNS
    }
    return jsonify(runs_data)


@app.route('/api/run/<path:run_path>')
def api_run_details(run_path):
    """Get details for a specific run."""
    run_dir = Path(run_path)
    
    if not run_dir.exists():
        return jsonify({'error': 'Run not found'}), 404
    
    try:
        # Check if this is an Owl run, GPT-5.4 run, or Claude run
        is_owl = is_owl_run(run_dir)
        is_gpt54 = is_gpt54_run(run_dir)

        if is_owl:
            # Load Owl data
            parsed_responses_json = run_dir / 'parsed_responses.json'
            info_json = run_dir / 'info.json'

            parsed_responses = load_owl_parsed_responses(str(parsed_responses_json)) if parsed_responses_json.exists() else []
            info = load_owl_info(str(info_json)) if info_json.exists() else {}
            summary = get_run_summary(str(run_dir))

            # Extract steps
            steps = extract_owl_trajectory_steps(parsed_responses, run_dir)

            # Task description - get from task.json if available
            task_description = ""
            # Try to extract from parent directory structure
            # Owl runs are typically in all_runs/owl-gui-normal-highres/mPLUG/GUI-Owl-32B/task_name/run_0
            task_name = run_dir.parent.name
            task_json_path = Path(f'examples/gimp_env_all/tasks/{task_name}/task.json')
            if task_json_path.exists():
                try:
                    with open(task_json_path, 'r') as f:
                        task_data = json.load(f)
                        task_description = task_data.get('description', '')
                except:
                    task_description = f"Task: {task_name}"
            else:
                task_description = f"Task: {task_name}"
        elif is_gpt54:
            # Load GPT-5.4 Computer Use data
            responses_meta_path = run_dir / 'responses_metadata.json'
            action_history_path = run_dir / 'action_history.json'
            info_json_path = run_dir / 'info.json'

            responses_metadata = []
            if responses_meta_path.exists():
                with open(responses_meta_path, 'r') as f:
                    responses_metadata = json.load(f)

            action_history = []
            if action_history_path.exists():
                with open(action_history_path, 'r') as f:
                    action_history = json.load(f)

            info = {}
            if info_json_path.exists():
                with open(info_json_path, 'r') as f:
                    info = json.load(f)

            summary = get_run_summary(str(run_dir))
            steps = extract_gpt54_trajectory_steps(responses_metadata, action_history, run_dir)

            # Task description from first response text or task name
            task_description = ""
            if responses_metadata and responses_metadata[0].get('text_output'):
                task_description = responses_metadata[0]['text_output']
            else:
                task_name = run_dir.parent.name
                task_description = f"Task: {task_name}"
        else:
            # Load Claude data
            messages_pkl = run_dir / 'messages.pkl'
            info_pkl = run_dir / 'info.pkl'

            messages = load_messages(str(messages_pkl)) if messages_pkl.exists() else []
            info = load_info(str(info_pkl)) if info_pkl.exists() else {}
            summary = get_run_summary(str(run_dir))

            # Extract steps
            steps = extract_trajectory_steps(messages, run_dir)

            # Task description
            task_description = ""
            if messages and messages[0].get('role') == 'user':
                content = messages[0].get('content', '')
                if isinstance(content, str):
                    task_description = content
                elif isinstance(content, list):
                    text_parts = []
                    for item in content:
                        if isinstance(item, dict) and item.get('type') == 'text':
                            text_parts.append(item.get('text', ''))
                        elif hasattr(item, 'type') and item.type == 'text':
                            text_parts.append(item.text if hasattr(item, 'text') else '')
                    task_description = ' '.join(text_parts) if text_parts else ""

        # Format steps for JSON
        # For Owl and GPT-5.4 runs, tool_calls are already formatted strings
        skip_format = is_owl or is_gpt54
        steps_data = []
        for step in steps:
            step_data = {
                'step_num': step['step_num'],
                'observation_path': str(step['observation_path']) if step['observation_path'] else None,
                'thinking': step['thinking'],
                'text_response': step['text_response'],
                'tool_calls': [tc if skip_format else format_tool_call(tc) for tc in step['tool_calls']],
                'tool_outputs': [str(to) for to in step['tool_outputs']]
            }
            steps_data.append(step_data)

        # Check if PDF and GIF exist
        pdf_exists = (run_dir / 'trajectory_report.pdf').exists()
        gif_exists = (run_dir / 'trajectory.gif').exists()

        return jsonify({
            'run_path': str(run_dir),
            'summary': summary,
            'task_description': task_description,
            'steps': steps_data,
            'total_steps': len(steps_data),
            'info': info,  # Include full info data
            'pdf_exists': pdf_exists,
            'gif_exists': gif_exists,
            'is_owl': is_owl
        })
    
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500


@app.route('/api/image/<path:image_path>')
def api_image(image_path):
    """Serve an observation image, with on-the-fly delta decompression."""
    img_path = Path(image_path)

    # If file exists directly, serve it
    if img_path.exists() and img_path.suffix == '.png':
        return send_file(str(img_path), mimetype='image/png')

    # Check if this is an observation file from a delta-compressed run
    if img_path.name.startswith('observation_') and img_path.suffix == '.png':
        run_dir = img_path.parent
        if has_delta_compression(run_dir):
            # Extract step number from filename (observation_N.png)
            try:
                step_num = int(img_path.stem.split('_')[1])
                png_bytes = get_delta_frame_as_png(run_dir, step_num)
                if png_bytes:
                    from io import BytesIO
                    return send_file(BytesIO(png_bytes), mimetype='image/png')
            except (ValueError, IndexError):
                pass

    return jsonify({'error': 'Image not found'}), 404


@app.route('/api/pdf/<path:run_path>')
def api_pdf(run_path):
    """Serve or generate PDF for a run."""
    run_dir = Path(run_path)
    pdf_path = run_dir / 'trajectory_report.pdf'
    
    if not pdf_path.exists():
        # Generate PDF if it doesn't exist
        try:
            from generate_pdf_report import create_pdf_report
            create_pdf_report(str(run_dir))
        except Exception as e:
            return jsonify({'error': f'Failed to generate PDF: {str(e)}'}), 500
    
    if pdf_path.exists():
        return send_file(str(pdf_path), mimetype='application/pdf')
    return jsonify({'error': 'PDF not found'}), 404


@app.route('/api/gif/<path:run_path>')
def api_gif(run_path):
    """Serve or generate GIF for a run."""
    run_dir = Path(run_path)
    gif_path = run_dir / 'trajectory.gif'
    
    if not gif_path.exists():
        # Generate GIF if it doesn't exist
        try:
            from generate_trajectory_gif import create_trajectory_gif
            create_trajectory_gif(str(run_dir))
        except Exception as e:
            return jsonify({'error': f'Failed to generate GIF: {str(e)}'}), 500
    
    if gif_path.exists():
        return send_file(str(gif_path), mimetype='image/gif')
    return jsonify({'error': 'GIF not found'}), 404


@app.route('/api/available_experiments')
def api_available_experiments():
    """Get list of available experiment-model pairs."""
    exp_model_pairs = {}
    
    # Build from already-loaded runs to handle nested structures correctly
    for run in ALL_RUNS:
        exp = run['experiment']
        model = run['model']
        
        if exp not in exp_model_pairs:
            exp_model_pairs[exp] = set()
        exp_model_pairs[exp].add(model)
    
    # Convert sets to sorted lists
    result = {exp: sorted(list(models)) for exp, models in exp_model_pairs.items()}
    
    return jsonify({'experiments': result})


@app.route('/api/statistics', methods=['POST'])
def api_statistics():
    """Compute statistics for selected experiment-model pairs."""
    data = request.get_json()
    pairs = data.get('pairs', [])
    
    if not pairs:
        return jsonify({'error': 'No experiment-model pairs provided'}), 400
    
    # Convert from list of dicts to list of tuples
    experiment_model_pairs = [(p['experiment'], p['model']) for p in pairs]
    
    result = compare_experiments(experiment_model_pairs)
    return jsonify(result)


def main(port=5000, debug=True):
    """Run the Flask app."""
    init_runs(constraint = sys.argv[2] if len(sys.argv) > 2 else None)
    print(f"\n{'='*80}")
    print("🚀 Trajectory Viewer Starting...")
    print(f"{'='*80}")
    print(f"Open your browser to: http://localhost:{port}")
    print(f"Total runs available: {len(ALL_RUNS)}")
    print(f"{'='*80}\n")
    
    app.run(host='0.0.0.0', port=port, debug=debug, use_reloader=False)


if __name__ == '__main__':
    print(sys.argv)
    main(port = 5000 if len(sys.argv) == 1 else int(sys.argv[1]))
