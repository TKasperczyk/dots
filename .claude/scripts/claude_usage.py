#!/usr/bin/env python3
"""Poll Claude Code OAuth usage limits. Caches aggressively to avoid 429s."""

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

CREDENTIALS = Path.home() / ".claude" / ".credentials.json"
CACHE_FILE = Path.home() / ".cache" / "eww" / "claude_usage.json"
CACHE_TTL = 300  # 5 minutes -- aggressive, relies on token refresh on 429

CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"

DEFAULT = json.dumps({
    "h5": 0, "h5_reset": "--:--",
    "d7": 0, "d7_reset": "---",
    "sonnet_d7": 0, "opus_d7": 0,
    "extra": False, "error": True
}, separators=(",", ":"))


def load_credentials():
    try:
        with open(CREDENTIALS) as f:
            return json.load(f)["claudeAiOauth"]
    except (FileNotFoundError, KeyError, json.JSONDecodeError):
        return None


def save_credentials(creds):
    data = {"claudeAiOauth": creds}
    tmp = str(CREDENTIALS) + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, CREDENTIALS)


def refresh_token(creds):
    body = json.dumps({
        "grant_type": "refresh_token",
        "refresh_token": creds["refreshToken"],
        "client_id": CLIENT_ID,
    }).encode()
    req = Request(TOKEN_URL, data=body, headers={"Content-Type": "application/json"})
    try:
        with urlopen(req, timeout=10) as resp:
            data = json.load(resp)
        creds["accessToken"] = data["access_token"]
        creds["refreshToken"] = data["refresh_token"]
        creds["expiresAt"] = int(time.time() * 1000) + data.get("expires_in", 3600) * 1000
        save_credentials(creds)
        return True
    except (HTTPError, URLError, KeyError):
        return False


def fetch_usage(token):
    req = Request(USAGE_URL, headers={
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
    })
    with urlopen(req, timeout=10) as resp:
        return json.load(resp)


def format_reset(iso_str):
    """Format reset time -- show HH:MM if today, else short date."""
    try:
        dt = datetime.fromisoformat(iso_str)
        now = datetime.now(timezone.utc)
        if dt.date() == now.date():
            return dt.strftime("%H:%M")
        return dt.strftime("%b %d")
    except (ValueError, TypeError):
        return "---"


def format_usage(raw):
    h5 = raw.get("five_hour") or {}
    d7 = raw.get("seven_day") or {}
    sonnet = raw.get("seven_day_sonnet") or {}
    opus = raw.get("seven_day_opus") or {}
    extra = raw.get("extra_usage") or {}

    return {
        "h5": int(h5.get("utilization", 0)),
        "h5_reset": format_reset(h5.get("resets_at")),
        "d7": int(d7.get("utilization", 0)),
        "d7_reset": format_reset(d7.get("resets_at")),
        "sonnet_d7": int(sonnet.get("utilization", 0)),
        "opus_d7": int(opus.get("utilization", 0)),
        "extra": bool(extra.get("is_enabled")),
        "error": False,
    }


def read_cache():
    try:
        with open(CACHE_FILE) as f:
            cached = json.load(f)
        age = time.time() - cached.get("_ts", 0)
        if age < CACHE_TTL:
            return cached, True  # valid cache
        return cached, False  # stale cache (usable as fallback)
    except (FileNotFoundError, json.JSONDecodeError):
        return None, False


def write_cache(data):
    cached = {**data, "_ts": time.time()}
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(CACHE_FILE, "w") as f:
        json.dump(cached, f, separators=(",", ":"))


def main():
    # Check cache first
    cached, valid = read_cache()
    if valid:
        out = {k: v for k, v in cached.items() if k != "_ts"}
        print(json.dumps(out, separators=(",", ":")))
        return

    creds = load_credentials()
    if not creds:
        print(DEFAULT)
        return

    # Refresh token if expired (with 5 min buffer)
    if creds.get("expiresAt", 0) < (time.time() * 1000 + 300_000):
        if not refresh_token(creds):
            # Token refresh failed -- return stale cache or default
            if cached:
                cached["error"] = True
                out = {k: v for k, v in cached.items() if k != "_ts"}
                print(json.dumps(out, separators=(",", ":")))
            else:
                print(DEFAULT)
            return

    # Fetch usage
    try:
        raw = fetch_usage(creds["accessToken"])
        result = format_usage(raw)
        write_cache(result)
        print(json.dumps(result, separators=(",", ":")))
    except HTTPError as e:
        if e.code == 429:
            # Rate limited -- try token refresh for fresh window
            if refresh_token(creds):
                try:
                    raw = fetch_usage(creds["accessToken"])
                    result = format_usage(raw)
                    write_cache(result)
                    print(json.dumps(result, separators=(",", ":")))
                    return
                except (HTTPError, URLError):
                    pass
            # Fall back to stale cache
            if cached:
                cached["error"] = True
                out = {k: v for k, v in cached.items() if k != "_ts"}
                print(json.dumps(out, separators=(",", ":")))
            else:
                print(DEFAULT)
        else:
            if cached:
                out = {k: v for k, v in cached.items() if k != "_ts"}
                print(json.dumps(out, separators=(",", ":")))
            else:
                print(DEFAULT)
    except (URLError, OSError):
        if cached:
            out = {k: v for k, v in cached.items() if k != "_ts"}
            print(json.dumps(out, separators=(",", ":")))
        else:
            print(DEFAULT)


if __name__ == "__main__":
    main()
