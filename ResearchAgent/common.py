"""Shared researcher limits, redaction, and process environment (no I/O at import)."""
from __future__ import annotations

import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional

MODEL_PROVIDER = "openai-codex"
MODEL_NAME = "gpt-5.6-luna"
MODEL_LABEL = MODEL_PROVIDER + "/" + MODEL_NAME
MAX_SESSIONS_PER_DATABASE = 300
MAX_DIGEST_CHARS = 90000
MAX_RECOMMENDATIONS = 4
MAX_TRANSCRIPT_CHARS = 12000
MIN_TRANSCRIPT_CHARS = 500
REQUEST_TIMEOUT_SECONDS = 20


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def emit_status(message: str) -> None:
    print("STATUS: " + message, file=sys.stderr, flush=True)


def truncate(value: str, limit: int) -> str:
    value = value.strip()
    if len(value) <= limit:
        return value
    return value[: max(0, limit - 1)].rstrip() + "…"


def redact(value: str) -> str:
    """Remove obvious credential-like values before any LLM call."""
    value = value.replace("\x00", " ")
    patterns = [
        (r"(?i)bearer\s+[A-Za-z0-9._~+/=-]{12,}", "Bearer [redacted]"),
        (r"""(?i)["']?(api[_ -]?key|access[_ -]?token|refresh[_ -]?token|secret)["']?\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;]+)""", r"\1=[redacted]"),
        (r"\bsk-[A-Za-z0-9_-]{12,}\b", "[redacted-key]"),
        (r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b", "[redacted-token]"),
        (r"\bAKIA[0-9A-Z]{16}\b", "[redacted-key]"),
        (r"""(?i)["']?(password|passwd|pwd)["']?\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;]+)""", r"\1=[redacted]"),
        (r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", "[redacted-email]"),
        (r"(?i)-----BEGIN [^-]+-----.*?-----END [^-]+-----", "[redacted-secret-block]"),
    ]
    for pattern, replacement in patterns:
        value = re.sub(pattern, replacement, value, flags=re.DOTALL)
    return value


def text_field(value, limit: int) -> str:
    return truncate(value, limit) if isinstance(value, str) else ""


def text_list(value, limit: int, count: int) -> list:
    """AI arrays must be arrays of strings, not strings iterated as characters."""
    if not isinstance(value, list):
        return []
    result = []
    for item in value:
        text = text_field(item, limit)
        if text:
            result.append(text)
            if len(result) >= count:
                break
    return result


def normalise_user_message(value: str) -> str:
    value = redact(value)
    value = re.sub(r"\s+", " ", value).strip()
    return value


def augmented_env(extra: Optional[Dict[str, str]] = None) -> Dict[str, str]:
    """Environment with a deliberate PATH so GUI-launched apps can find node and yt-dlp."""
    env = dict(os.environ)
    home_bin = str(Path.home() / ".local/bin")
    extra_dirs = ["/opt/homebrew/bin", "/usr/local/bin", home_bin, "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    current = env.get("PATH", "")
    env["PATH"] = ":".join(extra_dirs + ([current] if current else []))
    if extra:
        env.update(extra)
    return env
