"""Read-only, bounded user-authored context from local session databases."""
from __future__ import annotations

import json
import sqlite3
import urllib.parse
from collections import Counter
from contextlib import closing
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .common import MAX_DIGEST_CHARS, MAX_SESSIONS_PER_DATABASE, normalise_user_message, truncate


def database_paths(home: Optional[Path] = None) -> List[Path]:
    home = home or Path.home()
    hermes_home = home / ".hermes"
    candidates = [hermes_home / "state.db"]
    for root_name in ("agent-profiles", "profiles"):
        root = hermes_home / root_name
        if root.exists():
            candidates.extend(sorted(root.rglob("state.db")))
    result: List[Path] = []
    seen = set()
    for path in candidates:
        resolved = path.expanduser().resolve()
        if resolved not in seen and resolved.is_file():
            # Canonical paths deduplicate aliases, but keep the public path spelling.
            # On macOS resolve() changes /var to /private/var.
            result.append(path)
            seen.add(resolved)
    return result


def sqlite_connection(path: Path) -> sqlite3.Connection:
    uri = "file:" + urllib.parse.quote(str(path), safe="/") + "?mode=ro"
    return sqlite3.connect(uri, uri=True)


def _session_rows(connection: sqlite3.Connection):
    """Optional session metadata varies between historical Hermes schemas."""
    columns = {row[1] for row in connection.execute("pragma table_info(sessions)")}
    source = "source" if "source" in columns else "'unknown' as source"
    title = "title" if "title" in columns else "'' as title"
    profile = "coalesce(profile_name, '') as profile_name" if "profile_name" in columns else "'' as profile_name"
    if {"last_activity_at", "started_at"}.issubset(columns):
        activity = "coalesce(last_activity_at, started_at)"
    else:
        activity = next((name for name in ("last_activity_at", "started_at") if name in columns), "id")
    where = "where coalesce(archived, 0) = 0" if "archived" in columns else ""
    # All identifiers above are fixed literals, never values from the database.
    return connection.execute(
        f"select id, {source}, {title}, {profile} from sessions {where} order by {activity} desc limit ?",
        (MAX_SESSIONS_PER_DATABASE,),
    ).fetchall()


def _recent_excerpts(connection: sqlite3.Connection, session_id: str) -> List[str]:
    """Read newest first; stop once the same last eight usable messages are found."""
    excerpts: List[str] = []
    with closing(connection.execute(
        "select content from messages where session_id = ? and role = 'user' order by id desc",
        (session_id,),
    )) as messages:
        for message in messages:
            content = normalise_user_message(message[0] or "")
            if len(content) < 12:
                continue
            excerpts.append(truncate(content, 700))
            if len(excerpts) == 8:
                break
    return list(reversed(excerpts))


def session_digest(*, database_paths=database_paths, sqlite_connection=sqlite_connection) -> Tuple[str, Dict[str, Any]]:
    """Collect a size-capped, redacted digest. No assistant/tool messages are read."""
    lines: List[str] = []
    digest_chars = 0
    source_counts: Counter[str] = Counter()
    profile_names = set()
    db_count = 0
    skipped_count = 0
    full = False

    for path in database_paths():
        db_count += 1
        try:
            # sqlite Connection.__exit__ commits/rolls back; it does NOT close.
            with closing(sqlite_connection(path)) as connection:
                connection.row_factory = sqlite3.Row
                tables = {row[0] for row in connection.execute("select name from sqlite_master where type='table'")}
                if not {"sessions", "messages"}.issubset(tables):
                    skipped_count += 1
                    continue
                for row in _session_rows(connection):
                    excerpts = _recent_excerpts(connection, row["id"])
                    if not excerpts:
                        continue
                    source = truncate(normalise_user_message(str(row["source"] or "unknown")), 80)
                    profile = truncate(normalise_user_message(str(row["profile_name"] or "default")), 80)
                    block = {
                        "session": len(lines) + 1,
                        "source": source,
                        "profile": profile,
                        "title": truncate(normalise_user_message(str(row["title"] or "")), 140),
                        "messages": excerpts,
                    }
                    candidate = json.dumps(block, ensure_ascii=False, separators=(",", ":"))
                    added_chars = len(candidate) + bool(lines)
                    if digest_chars + added_chars > MAX_DIGEST_CHARS:
                        full = True
                        break
                    lines.append(candidate)
                    digest_chars += added_chars
                    profile_names.add(profile)
                    source_counts[source] += 1
        except (OSError, sqlite3.Error):
            skipped_count += 1
        if full:
            break

    audit = {
        "databasesScanned": db_count,
        "profilesSeen": len(profile_names),
        "sessionsIncluded": len(lines),
        "sourceCounts": dict(source_counts),
        "redaction": "user-authored messages only; credential-like values removed",
        "skippedDatabaseCount": skipped_count,
    }
    return "\n".join(lines), audit
