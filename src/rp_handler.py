import runpod
from runpod.serverless.utils import rp_upload
import json
import urllib.request
import time
import os
import requests
import base64
from io import BytesIO

COMFY_HOST = "127.0.0.1:8188"
COMFY_POLLING_INTERVAL_MS = int(os.environ.get("COMFY_POLLING_INTERVAL_MS", 250))
COMFY_POLLING_MAX_RETRIES = int(os.environ.get("COMFY_POLLING_MAX_RETRIES", 500))
REFRESH_WORKER = os.environ.get("REFRESH_WORKER", "false").lower() == "true"

def validate_input(job_input):
    if job_input is None:
        return None, "Please provide input"
    if isinstance(job_input, str):
        try:
            job_input = json.loads(job_input)
        except json.JSONDecodeError:
            return None, "Invalid JSON format in input"
    workflow = job_input.get("workflow")
    images = job_input.get("images")
    return {"workflow": workflow, "images": images}, None

def check_server(url, retries=500, delay=50):
    for _ in range(retries):
        try:
            r = requests.get(url)
            if r.status_code == 200:
                print(f"runpod-worker-comfy - API is reachable")
                return True
        except Exception:
            pass
        time.sleep(delay / 1000)
    return False

def upload_images(images):
    if not images:
        return {"status": "success", "message": "No images to upload", "details": []}
    responses, upload_errors = [], []
    print(f"runpod-worker-comfy - image(s) upload")
    for image in images:
        name, data = image["name"], image["image"]
        blob = base64.b64decode(data)
        files = {
            "image": (name, BytesIO(blob), "image/png"),
            "overwrite": (None, "true"),
        }
        r = requests.post(f"http://{COMFY_HOST}/upload/image", files=files)
        if r.status_code != 200:
            upload_errors.append(f"Error uploading {name}: {r.text}")
        else:
            responses.append(f"Successfully uploaded {name}")
    if upload_errors:
        return {"status": "error", "message": "Some images failed to upload", "details": upload_errors}
    return {"status": "success", "message": "All images uploaded successfully", "details": responses}

def queue_workflow(workflow):
    data = json.dumps({"prompt": workflow}).encode("utf-8")
    req = urllib.request.Request(f"http://{COMFY_HOST}/prompt", data=data)
    return json.loads(urllib.request.urlopen(req).read())

def get_history(prompt_id):
    with urllib.request.urlopen(f"http://{COMFY_HOST}/history/{prompt_id}") as response:
        return json.loads(response.read())

def base64_encode_file(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

def process_output_files(outputs, job_id):
    COMFY_OUTPUT_PATH = os.environ.get("COMFY_OUTPUT_PATH", "/comfyui/output")
    print(f"\n================ DEBUG: RAW OUTPUTS ================\n")
    print(json.dumps(outputs, indent=2))
    print(f"\n====================================================\n")

    output_file_path = None
    # Also check for gifs (because VHS_VideoCombine returns 'gifs')
    for node_id, node_output in outputs.items():
        for key in ["images", "videos", "gifs"]:
            if key in node_output:
                for file_info in node_output[key]:
                    output_file_path = os.path.join(COMFY_OUTPUT_PATH, file_info["subfolder"], file_info["filename"])
                    print(f"Detected output: {output_file_path}")
    if output_file_path and os.path.exists(output_file_path):
        if os.environ.get("BUCKET_ENDPOINT_URL"):
            return {"status": "success", "video_base64": rp_upload.upload_image(job_id, output_file_path)}
        else:
            return {"status": "success", "video_base64": base64_encode_file(output_file_path)}
    else:
        return {"status": "error", "message": "No images or videos were found in the workflow outputs."}

def handler(job):
    job_input = job["input"]
    validated_data, error_message = validate_input(job_input)
    if error_message:
        return {"error": error_message}
    workflow, images = validated_data["workflow"], validated_data["images"]
    check_server(f"http://{COMFY_HOST}")
    upload_result = upload_images(images)
    if upload_result["status"] == "error":
        return upload_result
    try:
        queued_workflow = queue_workflow(workflow)
        prompt_id = queued_workflow["prompt_id"]
        print(f"runpod-worker-comfy - queued workflow with ID {prompt_id}")
    except Exception as e:
        return {"error": f"Error queuing workflow: {str(e)}"}

    print("runpod-worker-comfy - waiting for workflow to complete")
    retries = 0
    while retries < COMFY_POLLING_MAX_RETRIES:
        history = get_history(prompt_id)
        if prompt_id in history and history[prompt_id].get("outputs"):
            break
        time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)
        retries += 1
    else:
        return {"error": "Max retries reached while waiting for image generation"}

    output_result = process_output_files(history[prompt_id].get("outputs"), job["id"])
    if output_result.get("status") != "success":
        raise ValueError(f"Job completed but failed: {output_result}")
    return {**output_result, "refresh_worker": REFRESH_WORKER}

if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})
