"""Tool-less Pi invocation and JSON decoding; never invokes a process on import."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Optional

from .common import MODEL_NAME, MODEL_PROVIDER, augmented_env, redact, truncate

def pi_path() -> Optional[str]:
    configured = os.environ.get("VAULTY_PI_PATH") or os.environ.get("KIVLET_PI_PATH") or os.environ.get("FOCUSVAULT_PI_PATH")
    candidates = [configured] if configured else []
    candidates.extend(["/opt/homebrew/bin/pi", "/usr/local/bin/pi"])
    discovered = shutil.which("pi")
    if discovered:
        candidates.append(discovered)
    for candidate in candidates:
        if candidate and Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def run_pi(prompt: str, timeout: int = 240, *, pi_path=pi_path, augmented_env=augmented_env) -> str:
    executable = pi_path()
    if not executable:
        raise RuntimeError("The pi CLI was not found. Install/configure Pi with the GPT-5.6 subscription.")

    prompt_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".md", prefix="vaulty-prompt-", delete=False, encoding="utf-8"
        ) as handle:
            prompt_path = Path(handle.name)
            handle.write(prompt)
        command = [
            executable,
            "--provider",
            MODEL_PROVIDER,
            "--model",
            MODEL_NAME,
            "--no-tools",
            "--no-session",
            "--print",
            "@" + str(prompt_path),
        ]
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            env=augmented_env({"NO_COLOR": "1"}),
        )
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout or "Pi returned a non-zero status").strip()
            raise RuntimeError("GPT-5.6 agent failed: " + truncate(redact(detail), 500))
        output = (completed.stdout or "").strip()
        if not output:
            raise RuntimeError("GPT-5.6 agent returned no output.")
        return output
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("GPT-5.6 agent timed out.") from exc
    except OSError as exc:
        raise RuntimeError("Could not start the GPT-5.6 agent: " + str(exc)) from exc
    finally:
        if prompt_path:
            try:
                prompt_path.unlink()
            except OSError:
                pass


def parse_json_output(value: str) -> Any:
    cleaned = value.strip()
    cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s*```$", "", cleaned)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        decoder = json.JSONDecoder()
        for match in re.finditer(r"[\[{]", cleaned):
            try:
                payload, _end = decoder.raw_decode(cleaned, match.start())
                return payload
            except json.JSONDecodeError:
                continue
        raise ValueError("The agent did not return a complete JSON document.")
