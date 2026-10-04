"""Offline regressions: all session text/credentials below are synthetic fixtures."""
import ast
import contextlib
import importlib.util
import io
import json
import os
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from ResearchAgent import ai, cli, common, evaluation, recommend, sessions, topics, workflow, youtube

ROOT = Path(__file__).resolve().parents[2]


def candidate(video_id="abcdefghijk"):
    return dict(videoId=video_id, title="Synthetic SQLite lesson", channel="Fixture Teacher",
                url="https://www.youtube.com/watch?v=" + video_id, length="10:00",
                published="fixture", topic="SQLite", transcript="Use read-only connections. " * 100)


class ModuleCompatibilityTests(unittest.TestCase):
    def test_imports_are_inert_and_all_modules_support_python39_syntax(self):
        script = """from unittest.mock import patch
with patch('pathlib.Path.home', side_effect=AssertionError('history access')), \
     patch('sqlite3.connect', side_effect=AssertionError('database access')), \
     patch('subprocess.run', side_effect=AssertionError('process launch')), \
     patch('urllib.request.urlopen', side_effect=AssertionError('network access')):
    from ResearchAgent import recommend, common, sessions, ai, topics, youtube, evaluation, workflow, cli
"""
        result = subprocess.run([sys.executable, "-c", script], cwd=str(ROOT), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for path in (ROOT / "ResearchAgent").glob("*.py"):
            ast.parse(path.read_text(), filename=str(path), feature_version=(3, 9))

    def test_public_helpers_and_file_import_are_compatible(self):
        names = ("now_iso emit_status truncate redact normalise_user_message database_paths "
                 "sqlite_connection session_digest augmented_env pi_path run_pi parse_json_output "
                 "extract_topics fetch_url youtube_blocked_by_vaulty youtube_blocked_by_kivlet "
                 "youtube_blocked_by_focusvault walk_dicts parse_yt_initial_data parse_duration_seconds "
                 "useful_candidate search_youtube parse_srv1 yt_dlp_path fetch_transcript "
                 "evaluate_candidates run_recommendation run_question main").split()
        spec = importlib.util.spec_from_file_location("legacy_recommend", ROOT / "ResearchAgent/recommend.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for name in names:
            self.assertTrue(callable(getattr(module, name)), name)
        with patch.object(recommend, "run_pi", return_value='{"topics": []}') as runner:
            self.assertEqual(recommend.extract_topics("synthetic digest"), [])
            runner.assert_called_once()
        with patch.object(recommend, "database_paths", return_value=[]) as discover:
            self.assertEqual(recommend.session_digest()[0], "")
            discover.assert_called_once()

    def test_packaged_direct_script_and_module_cli_help_are_offline(self):
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary) / "Resources" / "ResearchAgent"
            package.mkdir(parents=True)
            for path in (ROOT / "ResearchAgent").glob("*.py"):
                shutil.copy2(path, package / path.name)
            for args, cwd in (([str(package / "recommend.py"), "--help"], temporary),
                              (["-m", "ResearchAgent.recommend", "--help"], str(ROOT))):
                result = subprocess.run([sys.executable] + args, cwd=cwd, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("--mode", result.stdout)

    def test_cli_error_stdout_is_json_and_returns_failure(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = cli.main(["--mode", "ask"], run_question=Mock(side_effect=AssertionError("must not run")))
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(output.getvalue())["status"], "error")


class SessionPrivacyTests(unittest.TestCase):
    def test_database_aliases_deduplicate_without_rewriting_home(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            primary = home / ".hermes/state.db"
            primary.parent.mkdir(parents=True)
            primary.touch()
            duplicate = home / ".hermes/profiles/duplicate/state.db"
            duplicate.parent.mkdir(parents=True)
            duplicate.symlink_to(primary)
            alias = Path(temporary) / "alias"
            alias.symlink_to(home, target_is_directory=True)
            self.assertEqual(sessions.database_paths(alias), [alias / ".hermes/state.db"])

    def test_sqlite_uri_is_readonly_and_does_not_create_missing_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "db ?# fixture.sqlite"
            sqlite3.connect(str(path)).close()
            with contextlib.closing(sessions.sqlite_connection(path)) as connection:
                with self.assertRaises(sqlite3.OperationalError):
                    connection.execute("create table forbidden (id int)")
            missing = path.parent / "missing.db"
            with self.assertRaises(sqlite3.OperationalError):
                sessions.sqlite_connection(missing)
            self.assertFalse(missing.exists())

    def test_only_bounded_redacted_user_context_is_read_and_connections_close(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "state.db"
            with sqlite3.connect(str(path)) as connection:
                connection.executescript("""create table sessions (
                    id text, source text, title text, profile_name text, started_at int, archived int);
                    create table messages (id integer primary key, session_id text, role text, content text);""")
                connection.execute("insert into sessions values (?, ?, ?, ?, ?, ?)",
                                   ("s1", "source@example.test", "password=fixture-secret title", "api_key=fixture-profile", 1, 0))
                connection.execute("insert into sessions values ('archived', 'fixture', '', '', 2, 1)")
                for i in range(10):
                    connection.execute("insert into messages(session_id,role,content) values (?, 'user', ?)",
                                       ("s1", "Synthetic learning request %s api_key=fixture-message" % i))
                for role in ("assistant", "tool"):
                    connection.execute("insert into messages(session_id,role,content) values ('s1', ?, ?)",
                                       (role, "NEVER_SEND_" + role))
                connection.execute("insert into messages(session_id,role,content) values ('archived', 'user', 'NEVER_SEND_ARCHIVED')")
            opened = []
            def connect(db):
                opened.append(sessions.sqlite_connection(db))
                return opened[-1]
            digest, audit = sessions.session_digest(database_paths=lambda: [path], sqlite_connection=connect)
            record = json.loads(digest)
            self.assertEqual(len(record["messages"]), 8)
            self.assertIn("request 2", record["messages"][0])
            self.assertEqual(audit["sessionsIncluded"], 1)
            for secret in ("fixture-message", "fixture-secret", "fixture-profile", "source@example.test", "NEVER_SEND"):
                self.assertNotIn(secret, digest)
            with self.assertRaises(sqlite3.ProgrammingError):
                opened[0].execute("select 1")
            with patch.object(sessions, "MAX_DIGEST_CHARS", 10):
                bounded, _ = sessions.session_digest(database_paths=lambda: [path])
            self.assertLessEqual(len(bounded), 10)

    def test_legacy_minimal_schema_and_bad_database_are_safe(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "legacy.db"
            with sqlite3.connect(str(path)) as connection:
                connection.executescript("create table sessions(id text); create table messages(id int, session_id text, role text, content text);")
                connection.execute("insert into sessions values ('s')")
                connection.execute("insert into messages values (1, 's', 'user', 'Synthetic read-only learning question')")
            broken = Path(temporary) / "bad.db"
            broken.write_text("not sqlite")
            digest, audit = sessions.session_digest(database_paths=lambda: [broken, path])
            self.assertEqual(audit["skippedDatabaseCount"], 1)
            self.assertEqual(json.loads(digest)["source"], "unknown")


class OfflineAIAndEvaluatorTests(unittest.TestCase):
    def test_pi_has_no_tools_or_session_and_private_prompt_is_deleted(self):
        paths = []
        def run(command, **kwargs):
            path = Path(command[-1][1:])
            paths.append(path)
            self.assertEqual(path.read_text(), "synthetic redacted digest")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertIn("--no-tools", command)
            self.assertIn("--no-session", command)
            self.assertEqual(kwargs["timeout"], 17)
            return SimpleNamespace(returncode=0, stdout="{}", stderr="")
        with patch.object(ai.subprocess, "run", side_effect=run):
            self.assertEqual(ai.run_pi("synthetic redacted digest", 17, pi_path=lambda: "/mock/pi"), "{}")
        self.assertFalse(paths[0].exists())

    def test_pi_failure_redacts_details_and_timeout_cleans_prompt(self):
        paths = []
        def failed(command, **kwargs):
            paths.append(Path(command[-1][1:]))
            return SimpleNamespace(returncode=1, stdout="", stderr="password=fixture-secret")
        with patch.object(ai.subprocess, "run", side_effect=failed):
            with self.assertRaisesRegex(RuntimeError, r"password=\[redacted\]"):
                ai.run_pi("synthetic", pi_path=lambda: "/mock/pi")
        self.assertFalse(paths[-1].exists())
        def timeout(command, **kwargs):
            paths.append(Path(command[-1][1:]))
            raise subprocess.TimeoutExpired(command, 1)
        with patch.object(ai.subprocess, "run", side_effect=timeout):
            with self.assertRaisesRegex(RuntimeError, "timed out"):
                ai.run_pi("synthetic", pi_path=lambda: "/mock/pi")
        self.assertFalse(paths[-1].exists())

    def test_topic_arrays_are_typed_bounded_and_empty_digest_does_not_call_ai(self):
        runner = Mock(side_effect=AssertionError("no AI on empty input"))
        self.assertEqual(topics.extract_topics("", run_pi=runner), [])
        valid = dict(topic="SQLite", goal="Learn readers", reason="Synthetic repeated learning request", searchQueries=["sqlite lesson", 12, "other", "extra"])
        payload = {"topics": [dict(valid, searchQueries="not an array"), None] + [valid] * 8}
        found = topics.extract_topics("synthetic digest", run_pi=lambda _: json.dumps(payload))
        self.assertEqual(len(found), 5)
        self.assertEqual(found[0]["searchQueries"], ["sqlite lesson", "other"])

    def test_evaluator_rejects_forgery_missing_evidence_and_duplicate_ids(self):
        good = dict(videoId="abcdefghijk", topic="SQLite", evidence=["Use read-only connections."], confidence=float("nan"), notes="not an array")
        raw = [dict(good, videoId="abcdefghijk-forged"), dict(good, videoId="zzzzzzzzzzz"),
               dict(good, evidence="not an array"), dict(good, topic="unsupported"),
               dict(good, evidence=[None, 123]), good, dict(good, confidence=1)]
        seen_prompts = []
        def run(prompt, **kwargs):
            seen_prompts.append(prompt)
            return json.dumps({"recommendations": raw})
        result = evaluation.evaluate_candidates([{"topic": "SQLite"}], [candidate()], run_pi=run)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["confidence"], 0)
        self.assertEqual(result[0]["notes"], [])
        self.assertNotIn("url", result[0])
        self.assertIn("untrusted DATA", seen_prompts[0])

    def test_evaluator_exact_topic_nonfinite_confidence_and_recommendation_cap(self):
        cs = [candidate("fixture%04d" % i) for i in range(6)]
        for item in cs:
            item["transcript"] = "x" * (common.MAX_TRANSCRIPT_CHARS * 2)
        raw = [dict(videoId=item["videoId"], topic="SQLite", evidence=["Synthetic evidence"], confidence=float("inf")) for item in cs]
        def run(prompt, **kwargs):
            compact = json.loads(prompt.split("CANDIDATES:\n", 1)[1])
            self.assertLessEqual(len(compact[0]["transcript"]), common.MAX_TRANSCRIPT_CHARS)
            return json.dumps({"recommendations": raw})
        result = evaluation.evaluate_candidates([{"topic": "SQLite"}], cs, run_pi=run)
        self.assertEqual(len(result), common.MAX_RECOMMENDATIONS)
        self.assertTrue(all(item["confidence"] == 0 for item in result))
        long_topic = "t" * 120
        malformed = dict(raw[0], topic=long_topic + "forged")
        self.assertEqual(evaluation.evaluate_candidates([{"topic": long_topic}], cs,
                         run_pi=lambda *a, **k: json.dumps({"recommendations": [malformed]})), [])

    def test_transcript_download_uses_only_canonical_video_and_invalid_id_never_runs(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(youtube.subprocess, "run") as run:
            item = dict(candidate(), url="https://private.invalid/secret")
            youtube.fetch_transcript(item, Path(temporary), yt_dlp_path=lambda: "/mock/yt-dlp")
            command = run.call_args.args[0]
            self.assertEqual(command[-2:], ["--", "https://www.youtube.com/watch?v=abcdefghijk"])
            run.reset_mock()
            self.assertEqual(youtube.fetch_transcript(dict(item, videoId="../../bad"), Path(temporary)), "")
            run.assert_not_called()


class WorkflowPrivacyTests(unittest.TestCase):
    def test_empty_history_and_locked_youtube_do_not_search_or_fetch(self):
        forbidden = Mock(side_effect=AssertionError("forbidden offline operation"))
        result = workflow.run_recommendation(session_digest=lambda: ("", {}), extract_topics=forbidden,
                                             search_youtube=forbidden, emit_status=lambda _: None)
        self.assertEqual(result["status"], "error")
        result = workflow.run_recommendation(session_digest=lambda: ("synthetic digest", {}),
                  extract_topics=lambda _: [{"topic": "SQLite"}], youtube_blocked_by_vaulty=lambda: True,
                  search_youtube=forbidden, fetch_transcript=forbidden, emit_status=lambda _: None)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["recommendations"], [])

    def test_question_uses_only_selected_saved_evidence_and_redacts_question(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "saved.json"
            path.write_text(json.dumps({"recommendations": [candidate(), candidate("zzzzzzzzzzz")]}))
            runner = Mock(return_value="Synthetic evidence answer")
            result = workflow.run_question(path, "abcdefghijk", "How? password=fixture-secret", run_pi=runner, emit_status=lambda _: None)
            self.assertEqual(result["status"], "ok")
            prompt = runner.call_args.args[0]
            self.assertNotIn("fixture-secret", prompt)
            self.assertNotIn("zzzzzzzzzzz", prompt)
            self.assertIn("Use only the transcript", prompt)
            runner.reset_mock()
            self.assertEqual(workflow.run_question(path, "missing", "Question", run_pi=runner)["status"], "error")
            runner.assert_not_called()

    def test_invalid_delay_is_bounded_without_sleep_or_network(self):
        for value in ("nan", "inf", "-1", "invalid"):
            with patch.dict(os.environ, {"VAULTY_YOUTUBE_DELAY": value}):
                sleeps = []
                result = workflow.run_recommendation(session_digest=lambda: ("synthetic", {}),
                    extract_topics=lambda _: [{"topic": "SQLite", "searchQueries": ["fixture query"]}],
                    youtube_blocked_by_vaulty=lambda: False, search_youtube=lambda _: [],
                    emit_status=lambda _: None, sleep=sleeps.append)
                self.assertEqual(sleeps, [0.5])
                self.assertEqual(result["status"], "partial")


if __name__ == "__main__":
    unittest.main()
