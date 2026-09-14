"""Read recent checks from DynamoDB and publish a status summary to S3."""

import json
import os
import time
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ["TABLE_NAME"]
BUCKET = os.environ["BUCKET"]
TARGETS = [t.strip() for t in os.environ["TARGETS"].split(",") if t.strip()]
WINDOW_HOURS = int(os.environ.get("WINDOW_HOURS", "24"))
SAMPLE_LIMIT = int(os.environ.get("SAMPLE_LIMIT", "60"))

table = boto3.resource("dynamodb").Table(TABLE_NAME)
s3 = boto3.client("s3")


def number(value):
    """DynamoDB returns Decimal; JSON does not know what to do with it."""
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    return value


def summarise(url, since):
    """Build one target's summary from its recent checks."""
    response = table.query(
        KeyConditionExpression=Key("target").eq(
            url) & Key("checked_at").gte(since),
        ScanIndexForward=False,
        Limit=500,
    )
    items = response.get("Items", [])

    if not items:
        return {
            "target": url,
            "status": "unknown",
            "checks": 0,
            "uptime_percent": None,
            "last_checked": None,
            "samples": [],
        }

    total = len(items)
    up_count = sum(1 for i in items if i.get("up"))
    latest = items[0]

    latencies = [number(i["latency_ms"]) for i in items if i.get("up")]
    average_latency = round(
        sum(latencies) / len(latencies)) if latencies else None

    # Oldest first, so the page can draw them left to right.
    samples = [
        {
            "at": number(i["checked_at"]),
            "up": bool(i.get("up")),
            "ms": number(i.get("latency_ms", 0)),
        }
        for i in reversed(items[:SAMPLE_LIMIT])
    ]

    return {
        "target": url,
        "status": "up" if latest.get("up") else "down",
        "checks": total,
        "uptime_percent": round(up_count / total * 100, 2),
        "average_latency_ms": average_latency,
        "last_checked": number(latest["checked_at"]),
        "last_status_code": number(latest.get("status_code")) if latest.get("status_code") else None,
        "last_error": latest.get("error"),
        "samples": samples,
    }


def handler(event, context):
    now = int(time.time())
    since = now - WINDOW_HOURS * 3600

    targets = [summarise(url, since) for url in TARGETS]
    down = [t for t in targets if t["status"] == "down"]

    payload = {
        "generated_at": now,
        "window_hours": WINDOW_HOURS,
        "overall": "down" if down else "up",
        "targets": targets,
    }

    s3.put_object(
        Bucket=BUCKET,
        Key="status.json",
        Body=json.dumps(payload, indent=2).encode("utf-8"),
        ContentType="application/json",
        # Short cache: the page should not show stale data for long, but we
        # also do not want every visitor hitting the origin.
        CacheControl="public, max-age=60",
    )

    print(json.dumps({"event": "published",
          "targets": len(targets), "down": len(down)}))
    return {"published": len(targets), "down": len(down)}
