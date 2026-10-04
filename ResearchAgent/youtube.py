"""YouTube search/captions and managed-hosts checks, independent of AI and sessions."""
from __future__ import annotations

import html
import json
import os
import re
import shutil
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

from .common import MIN_TRANSCRIPT_CHARS, MAX_TRANSCRIPT_CHARS, REQUEST_TIMEOUT_SECONDS, augmented_env, truncate

def fetch_url(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15",
            "Accept-Language": "en-AU,en;q=0.9",
        },
    )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        return response.read(5_000_000).decode("utf-8", "replace")


def youtube_blocked_by_vaulty(hosts_path: Optional[Path] = None) -> bool:
    hosts_path = hosts_path or Path("/etc/hosts")
    try:
        contents = hosts_path.read_text(encoding="utf-8")
    except OSError:
        return False

    marker_pairs = [
        ("# BEGIN VAULTY MANAGED BLOCK", "# END VAULTY MANAGED BLOCK"),
        ("# BEGIN KIVLET MANAGED BLOCK", "# END KIVLET MANAGED BLOCK"),
        ("# BEGIN FOCUSVAULT MANAGED BLOCK", "# END FOCUSVAULT MANAGED BLOCK"),
        ("# BEGIN FROSTWALL MANAGED BLOCK", "# END FROSTWALL MANAGED BLOCK"),
    ]
    for begin_marker, end_marker in marker_pairs:
        managed_lines = contents.split(begin_marker, 1)
        if len(managed_lines) != 2:
            continue
        managed_section = managed_lines[1].split(end_marker, 1)[0]
        return any(
            re.match(r"^\s*0\.0\.0\.0\s+(?:www\.)?youtube\.com\s*$", line, flags=re.IGNORECASE)
            for line in managed_section.splitlines()
        )
    return False


def walk_dicts(value: Any) -> Iterable[Dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk_dicts(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_dicts(child)


def parse_yt_initial_data(page: str) -> List[Dict[str, str]]:
    data = None
    decoder = json.JSONDecoder()
    # Decode the JSON itself rather than guessing where a nested object ends.
    for match in re.finditer(r"(?:\bytInitialData|window\[['\"]ytInitialData['\"]\])\s*=\s*", page):
        try:
            data, _end = decoder.raw_decode(page, match.end())
            break
        except json.JSONDecodeError:
            continue
    if data is None:
        return []

    candidates: List[Dict[str, str]] = []
    for item in walk_dicts(data):
        renderer = item.get("videoRenderer")
        if not isinstance(renderer, dict):
            continue
        video_id = str(renderer.get("videoId", "")).strip()
        if not re.fullmatch(r"[A-Za-z0-9_-]{11}", video_id):
            continue
        title_runs = renderer.get("title", {}).get("runs", [])
        title = "".join(str(run.get("text", "")) for run in title_runs if isinstance(run, dict)).strip()
        owner_runs = renderer.get("ownerText", {}).get("runs", [])
        channel = "".join(str(run.get("text", "")) for run in owner_runs if isinstance(run, dict)).strip()
        length = str(renderer.get("lengthText", {}).get("simpleText", "")).strip()
        published = str(renderer.get("publishedTimeText", {}).get("simpleText", "")).strip()
        description_snippets = renderer.get("detailedMetadataSnippets", [])
        description = ""
        if description_snippets and isinstance(description_snippets[0], dict):
            snippet = description_snippets[0].get("snippetText", {}).get("runs", [])
            description = "".join(str(run.get("text", "")) for run in snippet if isinstance(run, dict)).strip()
        candidates.append(
            {
                "videoId": video_id,
                "title": truncate(html.unescape(title), 220),
                "channel": truncate(html.unescape(channel), 120),
                "length": length,
                "published": published,
                "description": truncate(html.unescape(description), 260),
                "url": "https://www.youtube.com/watch?v=" + video_id,
            }
        )
    return candidates


def parse_duration_seconds(value: str) -> Optional[int]:
    if not value:
        return None
    pieces = value.split(":")
    try:
        numbers = [int(piece) for piece in pieces]
    except ValueError:
        return None
    total = 0
    for number in numbers:
        total = total * 60 + number
    return total


def useful_candidate(candidate: Dict[str, str]) -> bool:
    title = candidate.get("title", "").lower()
    if any(word in title for word in ("compilation", "reaction", "playlist", "trailer", "shorts")):
        return False
    duration = parse_duration_seconds(candidate.get("length", ""))
    return duration is None or duration >= 120


def search_youtube(query: str, *, fetch_url=fetch_url) -> List[Dict[str, str]]:
    encoded = urllib.parse.quote_plus(query)
    urls = [
        "https://www.youtube.com/results?search_query=" + encoded,
        "https://r.jina.ai/http://www.youtube.com/results?search_query=" + encoded,
    ]
    for url in urls:
        try:
            page = fetch_url(url)
            candidates = [item for item in parse_yt_initial_data(page) if useful_candidate(item)]
            if candidates:
                return candidates
            # Jina sometimes emits readable links without the original JSON.
            for video_id in dict.fromkeys(re.findall(r"(?:watch\?v=|youtu\.be/)([A-Za-z0-9_-]{11})", page)):
                candidates.append(
                    {
                        "videoId": video_id,
                        "title": "YouTube video " + video_id,
                        "channel": "",
                        "length": "",
                        "published": "",
                        "description": "",
                        "url": "https://www.youtube.com/watch?v=" + video_id,
                    }
                )
            if candidates:
                return candidates
        except (OSError, ValueError, urllib.error.URLError):
            continue
    return []


def parse_srv1(path: Path) -> str:
    try:
        root = ET.parse(str(path)).getroot()
    except (ET.ParseError, OSError):
        return ""
    parts = [html.unescape(text.strip()) for text in root.itertext() if text.strip()]
    return re.sub(r"\s+", " ", " ".join(parts)).strip()


def yt_dlp_path() -> Optional[str]:
    configured = os.environ.get("VAULTY_YTDLP_PATH") or os.environ.get("KIVLET_YTDLP_PATH") or os.environ.get("FOCUSVAULT_YTDLP_PATH")
    candidates = [configured] if configured else []
    candidates.extend(["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"])
    discovered = shutil.which("yt-dlp")
    if discovered:
        candidates.append(discovered)
    for candidate in candidates:
        if candidate and Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def fetch_transcript(candidate: Dict[str, str], directory: Path, *, yt_dlp_path=yt_dlp_path, augmented_env=augmented_env, parse_srv1=parse_srv1) -> str:
    video_id = candidate.get("videoId", "")
    if not isinstance(video_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{11}", video_id):
        return ""
    # Only the canonical public video may be downloaded, never a saved/AI URL.
    url = "https://www.youtube.com/watch?v=" + video_id
    executable = yt_dlp_path()
    if not executable:
        return ""
    base = directory / video_id
    command = [
        executable,
        "--write-subs",
        "--write-auto-subs",
        "--sub-langs",
        "en-orig,en",
        "--skip-download",
        "--no-playlist",
        "--sub-format",
        "srv1",
        "--no-warnings",
        "-o",
        str(base),
        "--",
        url,
    ]
    try:
        subprocess.run(command, capture_output=True, text=True, timeout=55, check=False, env=augmented_env())
    except (OSError, subprocess.TimeoutExpired):
        return ""
    files = sorted(directory.glob(video_id + ".*.srv1"))
    for path in files:
        try:
            if path.stat().st_size < 1_000:
                continue
        except OSError:
            continue
        transcript = parse_srv1(path)
        if len(transcript) >= MIN_TRANSCRIPT_CHARS:
            return truncate(transcript, MAX_TRANSCRIPT_CHARS)
    return ""


# Historical public names remain supported.
youtube_blocked_by_kivlet = youtube_blocked_by_vaulty
youtube_blocked_by_focusvault = youtube_blocked_by_vaulty
