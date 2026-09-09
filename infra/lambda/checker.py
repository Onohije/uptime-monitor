"""Probe each target URL and record the result in DynamoDB."""

import json
import os
import time
import urllib.error
import urllib.request

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
TARGETS = [t.strip() for t in os.environ["TARGETS"].split(",") if t.strip()]
TIMEOUT_SECONDS = int(os.environ.get("TIMEOUT_SECONDS", "10"))
RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "30"))

table = boto3.resource("dynamodb").Table(TABLE_NAME)


def probe(url):
    """Return a result dict for one URL. Never raises."""
    started = time.monotonic()
    request = urllib.request.Request(
        url,
        method="GET",
        headers={"User-Agent": "uptime-monitor/1.0"},
    )

    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            status = response.status
            error = None
    except urllib.error.HTTPError as exc:
        # The server answered, just not with a 2xx. That is still a response.
        status = exc.code
        error = None
    except Exception as exc:
        # DNS failure, connection refused, TLS error, timeout.
        status = None
        error = f"{type(exc).__name__}: {exc}"

    latency_ms = int((time.monotonic() - started) * 1000)
    return {
        "status_code": status,
        "latency_ms": latency_ms,
        "up": status is not None and 200 <= status < 400,
        "error": error,
    }


def handler(event, context):
    checked_at = int(time.time())
    expires_at = checked_at + RETENTION_DAYS * 86400
    results = []

    for url in TARGETS:
        result = probe(url)
        item = {
            "target": url,
            "checked_at": checked_at,
            "expires_at": expires_at,
            "latency_ms": result["latency_ms"],
            "up": result["up"],
        }
        if result["status_code"] is not None:
            item["status_code"] = result["status_code"]
        if result["error"] is not None:
            item["error"] = result["error"]

        table.put_item(Item=item)

        # One structured log line per check, so CloudWatch Logs Insights can query it.
        print(json.dumps({"event": "check", **item}))
        results.append(item)

    return {"checked": len(results), "down": sum(1 for r in results if not r["up"])}
