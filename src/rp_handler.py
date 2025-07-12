#!/usr/bin/env python3
import runpod
from runpod.serverless.utils import rp_upload
import json
import urllib.request
import urllib.parse
import time
import os
import requests
import base64
from io import BytesIO

COMFY_API_AVAILABLE_INTERVAL_MS = 50
COMFY_API_AVAILABLE_MAX_RETRIES = 500
COMFY_POLLING_INTERVAL_MS = int(os.environ.get("COMFY_POLLING_INTERVAL_MS", 250))
COMFY_POLLING_MAX_RETRIES = int(os.environ.get("COMFY_POLLING_MAX_RETRIES", 500))
COMFY_HOST = "127.0.0.1:8188"
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
    if workflow is None:
        return None, "Missing 'workflow' parameter"

    images = job_input.get("images")
    if images is not None:
        if not isinstance(images, list) or not all("name" in image and "image" in image for image in images):
            return None, "'images' must be a list of objects with 'name' and 'image' keys"

    return {"workflow": workflow, "images": images}, None


def check_server(url, retries=500, delay=50):
    for _ in range(retries):
        try:
            response = requests.get(url)
            if response.status_code == 200:
                print(f"runpod-worker-comfy - API is reachable")
                return True
        except requests.RequestException:
            pass
        time.sleep(delay / 1000)
    print(f"runpod-worker-comfy - Failed to connect to server at {url}")
    return False


def upload_images(images):
    if not images:
        return {"status": "success", "message": "No images to upload", "details": []}

    responses = []
    upload_errors = []

    print(f"runpod-worker-comfy - image(s) upload")

    for image in images:
        name = image["name"]
        blob = base64.b64decode(image["image"])
        files = {
            "image": (name, BytesIO(blob), "image/png"),
            "overwrite": (None, "true"),
        }
        response = requests.post(f"http://{COMFY_HOST}/upload/image", files=files)
        if response.status_code != 200:
            upload_errors.append(f"Error uploading {name}: {response.text}")
        else:
            responses.append(f"Successfully uploaded {name}")

    if upload_errors:
        print(f"runpod-worker-comfy - image(s) upload with errors")
        return {"status": "error", "message": "Some images failed to upload", "details": upload_errors}

    print(f"runpod-worker-comfy - image(s) upload complete")
    return {"status": "success", "message": "All images uploaded successfully", "details": responses}


def queue_workflow(workflow):
    data = json.dumps({"prompt": workflow}).encode("utf-8")
    req = urllib.request.Request(f"http://{COMFY_HOST}/prompt", data=data)
    return json.loads(urllib.request.urlopen(req).read())


def get_history(prompt_id):
    with urllib.request.urlopen(f"http://{COMFY_HOST}/history/{prompt_id}") as response:
        return json.loads(response.read())


def base64_encode(file_path):
    with open(file_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def process_output_files(outputs, job_id):
    COMFY_OUTPUT_PATH = os.environ.get("COMFY_OUTPUT_PATH", "/comfyui/output")
    output_file_path = None

    for node_id, node_output in outputs.items():
        if "images" in node_output:
            for image in node_output["images"]:
                output_file_path = os.path.join(image["subfolder"], image["filename"])
        elif "videos" in node_output:
            for video in node_output["videos"]:
                output_file_path = os.path.join(video["subfolder"], video["filename"])

    if not output_file_path:
        return {"status": "error", "message": "No images or videos were found in the workflow outputs."}

    local_file_path = os.path.join(COMFY_OUTPUT_PATH, output_file_path)

    if os.path.exists(local_file_path):
        if os.environ.get("BUCKET_ENDPOINT_URL"):
            url_or_data = rp_upload.upload_image(job_id, local_file_path)
        else:
            url_or_data = base64_encode(local_file_path)
        return {"status": "success", "message": url_or_data}
    else:
        return {"status": "error", "message": f"The file does not exist: {local_file_path}"}


def handler(job):
    job_input = job["input"]
    validated_data, error_message = validate_input(job_input)
    if error_message:
        return {"error": error_message}

    workflow = validated_data["workflow"]
    images = validated_data.get("images")

    check_server(f"http://{COMFY_HOST}", COMFY_API_AVAILABLE_MAX_RETRIES, COMFY_API_AVAILABLE_INTERVAL_MS)

    upload_result = upload_images(images)
    if upload_result["status"] == "error":
        return upload_result

    try:
        queued_workflow = queue_workflow(workflow)
        prompt_id = queued_workflow["prompt_id"]
        print(f"runpod-worker-comfy - queued workflow with ID {prompt_id}")
    except Exception as e:
        return {"error": f"Error queuing workflow: {str(e)}"}

    print(f"runpod-worker-comfy - wait until image generation is complete")
    retries = 0
    try:
        while retries < COMFY_POLLING_MAX_RETRIES:
            history = get_history(prompt_id)
            if prompt_id in history and history[prompt_id].get("outputs"):
                break
            time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)
            retries += 1
        else:
            return {"error": "Max retries reached while waiting for image generation"}
    except Exception as e:
        return {"error": f"Error waiting for image generation: {str(e)}"}

    output_result = process_output_files(history[prompt_id].get("outputs"), job["id"])

    if output_result["status"] != "success":
        raise ValueError(f"Job completed but failed: {output_result}")

    return {**output_result, "refresh_worker": REFRESH_WORKER}


if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})
