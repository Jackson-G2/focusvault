#!/usr/bin/env python3
"""Stable script entrypoint and patchable compatibility API for Vaulty's researcher.

Implementation lives in focused modules. Wrappers deliberately resolve public
helpers at call time so existing mocks/clients of ``recommend`` keep working.
Importing this module never reads history, starts Pi, or contacts the network.
"""
from __future__ import annotations

# Direct execution by the app and package imports share the same implementation.
if __package__ in (None, ""):
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ResearchAgent import ai, cli, evaluation, sessions, topics, workflow, youtube
from ResearchAgent.common import (
    MODEL_PROVIDER, MODEL_NAME, MODEL_LABEL, MAX_SESSIONS_PER_DATABASE,
    MAX_DIGEST_CHARS, MAX_RECOMMENDATIONS, MAX_TRANSCRIPT_CHARS,
    MIN_TRANSCRIPT_CHARS, REQUEST_TIMEOUT_SECONDS, augmented_env,
    now_iso, emit_status, truncate, redact, normalise_user_message,
)
from ResearchAgent.sessions import database_paths, sqlite_connection
from ResearchAgent.ai import pi_path, parse_json_output
from ResearchAgent.youtube import (
    fetch_url, youtube_blocked_by_vaulty, youtube_blocked_by_kivlet,
    youtube_blocked_by_focusvault, walk_dicts, parse_yt_initial_data,
    parse_duration_seconds, useful_candidate, parse_srv1, yt_dlp_path,
)


def session_digest():
    return sessions.session_digest(database_paths=database_paths, sqlite_connection=sqlite_connection)


def run_pi(prompt, timeout=240):
    return ai.run_pi(prompt, timeout, pi_path=pi_path, augmented_env=augmented_env)


def extract_topics(digest):
    return topics.extract_topics(digest, run_pi=run_pi, parse_json_output=parse_json_output)


def search_youtube(query):
    return youtube.search_youtube(query, fetch_url=fetch_url)


def fetch_transcript(candidate, directory):
    return youtube.fetch_transcript(candidate, directory, yt_dlp_path=yt_dlp_path,
                                    augmented_env=augmented_env, parse_srv1=parse_srv1)


def evaluate_candidates(topics, candidates):
    return evaluation.evaluate_candidates(topics, candidates, run_pi=run_pi,
                                          parse_json_output=parse_json_output)


def run_recommendation():
    return workflow.run_recommendation(
        session_digest=session_digest, extract_topics=extract_topics,
        youtube_blocked_by_vaulty=youtube_blocked_by_vaulty, search_youtube=search_youtube,
        fetch_transcript=fetch_transcript, evaluate_candidates=evaluate_candidates,
        emit_status=emit_status, now_iso=now_iso,
    )


def run_question(result_file, video_id, question):
    return workflow.run_question(result_file, video_id, question, run_pi=run_pi, emit_status=emit_status)


def main(argv=None):
    return cli.main(argv, run_recommendation=run_recommendation, run_question=run_question, now_iso=now_iso)


if __name__ == "__main__":
    raise SystemExit(main())
