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
    print(f"runpod-worker-comfy - Failed to connect to server at {url} after {retries} attempts.")
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

def base64_encode(img_path):
    with open(img_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

def process_output_images(outputs, job_id):
    COMFY_OUTPUT_PATH = os.environ.get("COMFY_OUTPUT_PATH", "/comfyui/output")

    for node_id, node_output in outputs.items():
        if "images" in node_output:
            for image in node_output["images"]:
                local_path = os.path.join(COMFY_OUTPUT_PATH, image["subfolder"], image["filename"])
                print(f"runpod-worker-comfy - checking for image at {local_path}")
                if os.path.exists(local_path):
                    if os.environ.get("BUCKET_ENDPOINT_URL"):
                        uploaded_url = rp_upload.upload_image(job_id, local_path)
                        return {"status": "success", "message": uploaded_url}
                    else:
                        b64_image = base64_encode(local_path)
                        return {"status": "success", "message": b64_image}
                else:
                    print(f"runpod-worker-comfy - file does not exist at {local_path}")

    return {
        "status": "error",
        "message": "No images were found in the workflow outputs."
    }

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
        queued = queue_workflow(workflow)
        prompt_id = queued["prompt_id"]
        print(f"runpod-worker-comfy - queued workflow with ID {prompt_id}")
    except Exception as e:
        return {"error": f"Error queuing workflow: {str(e)}"}

    print(f"runpod-worker-comfy - waiting for image generation")
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

    return {**process_output_images(history[prompt_id]["outputs"], job["id"]), "refresh_worker": REFRESH_WORKER}

if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})
