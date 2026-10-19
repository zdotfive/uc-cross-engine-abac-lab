"""Small REST helpers for the reader service principal. Nothing secret is printed."""
import json, os
import requests
from dotenv import dotenv_values

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
env = dotenv_values(os.path.join(ROOT, ".env"))
HOST = env["DATABRICKS_HOST"].rstrip("/")
IRC = f"{HOST}/api/2.1/unity-catalog/iceberg-rest/v1/catalogs/labs"
SECRETY = ("secret", "token", "key", "signature", "credential")


def reader_headers():
    r = requests.post(f"{HOST}/oidc/v1/token", auth=(env["DATABRICKS_CLIENT_ID"], env["DATABRICKS_CLIENT_SECRET"]),
                      data={"grant_type": "client_credentials", "scope": "all-apis"})
    r.raise_for_status()
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def redact(d):
    """Replace values of secret-looking keys; keep structure and key names."""
    if isinstance(d, dict):
        return {k: ("<redacted>" if any(s in k.lower() for s in SECRETY) and not isinstance(v, (list, dict))
                    else redact(v)) for k, v in d.items()}
    if isinstance(d, list):
        return [redact(x) for x in d]
    if isinstance(d, str) and ("X-Amz-Signature" in d or "X-Amz-Security-Token" in d):
        return d.split("?")[0] + "?<presigned-redacted>"
    return d


def short(resp, n=700):
    try:
        body = json.dumps(redact(resp.json()))
    except ValueError:
        body = resp.text
    return f"HTTP {resp.status_code} {body[:n]}"
