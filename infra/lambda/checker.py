cat > ~/uptime-monitor/infra/lambda/checker.py <<'PYEOF'
"""Probe each target URL, record the result, and alert on state changes."""

import json
import os
import time
import urllib.error
import urllib.request

import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ["TABLE_NAME"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
TARGETS = [t.strip() for t in os.environ["TARGETS"].split(",") if t.strip()]
TIMEOUT_SECONDS = int(os.environ.get("TIMEOUT_SECONDS", "10"))
RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "30"))

table = boto3.resource("dynamodb").Table(TABLE_NAME)
sns = boto3.client("sns")


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
        status = exc.code
        error = None
    except Exception as exc:
        status = None
        error = f"{type(exc).__name__}: {exc}"

    latency_ms = int((time.monotonic() - started) * 1000)
    return {
        "status_code": status,
        "latency_ms": latency_ms,
        "up": status is not None and 200 <= status < 400,
        "error": error,
    }


def previous_state(url):
    """The 'up' value of the most recent stored check, or None if this is the first."""
    response = table.query(
        KeyConditionExpression=Key("target").eq(url),
        ScanIndexForward=False,
        Limit=1,
        ProjectionExpression="up",
    )
    items = response.get("Items", [])
    return items[0]["up"] if items else None


def alert(url, item):
    """Publish a state-change notification."""
    going_down = not item["up"]
    subject = f"{'DOWN' if going_down else 'RECOVERED'}: {url}"

    if going_down:
        detail = item.get("error") or f"HTTP {item.get('status_code')}"
        body = f"{url} is not responding correctly.\n\nDetail: {detail}"
    else:
        body = f"{url} is responding again.\n\nHTTP {item.get('status_code')} in {item['latency_ms']}ms"

    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject=subject[:100],
        Message=f"{body}\n\nChecked at {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime(item['checked_at']))}",
    )


def handler(event, context):
    checked_at = int(time.time())
    expires_at = checked_at + RETENTION_DAYS * 86400
    results = []
    alerts_sent = 0

    for url in TARGETS:
        # Read the previous state BEFORE writing this one, or we would just
        # read back what we are about to store.
        was_up = previous_state(url)

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

        # Alert only on transitions. A target that has been down for a day
        # produced one email, not 288 of them.
        changed = was_up is not None and was_up != result["up"]
        first_check_and_down = was_up is None and not result["up"]

        if changed or first_check_and_down:
            try:
                alert(url, item)
                alerts_sent += 1
            except Exception as exc:
                # A failed notification must not lose the check result.
                print(json.dumps({"event": "alert_failed", "target": url, "error": str(exc)}))

        print(json.dumps({"event": "check", **item}))
        results.append(item)

    return {
        "checked": len(results),
        "down": sum(1 for r in results if not r["up"]),
        "alerts": alerts_sent,
    }
PYEOF

cd ~/uptime-monitor && terraform fmt -recursive
git add -A && git commit -m "Add SNS alerting on up/down transitions" && git push