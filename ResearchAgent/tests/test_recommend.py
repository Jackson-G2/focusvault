import json
import tempfile
import unittest
from pathlib import Path

from ResearchAgent.recommend import (
    database_paths,
    parse_duration_seconds,
    parse_json_output,
    parse_srv1,
    parse_yt_initial_data,
    redact,
    useful_candidate,
    youtube_blocked_by_focusvault,
    youtube_blocked_by_vaulty,
)


class RecommendationHelperTests(unittest.TestCase):
    def test_redacts_credential_like_values(self):
        value = redact("api_key=sk-secret-value-123456 password: supersecret bearer abcdefghijklmnop email user@example.com")
        self.assertIn("[redacted]", value)
        self.assertIn("[redacted-email]", value)
        self.assertNotIn("sk-secret-value-123456", value)
        self.assertNotIn("supersecret", value)
        self.assertNotIn("abcdefghijklmnop", value)
        self.assertNotIn("user@example.com", value)

    def test_extracts_json_from_markdown_fence(self):
        self.assertEqual(parse_json_output("```json\n{\"topics\": []}\n```"), {"topics": []})

    def test_parses_youtube_initial_data(self):
        payload = {
            "contents": {
                "videoRenderer": {
                    "videoId": "abcdefghijk",
                    "title": {"runs": [{"text": "Useful Lesson"}]},
                    "ownerText": {"runs": [{"text": "Good Teacher"}]},
                    "lengthText": {"simpleText": "12:34"},
                }
            }
        }
        page = "<script>var ytInitialData = " + json.dumps(payload) + ";</script>"
        results = parse_yt_initial_data(page)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["videoId"], "abcdefghijk")
        self.assertEqual(results[0]["title"], "Useful Lesson")
        self.assertEqual(results[0]["channel"], "Good Teacher")

    def test_parses_srv1_transcript(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "captions.srv1"
            path.write_text(
                '<transcript><text start="0" dur="1">Hello &amp; welcome.</text>'
                '<text start="1" dur="1">Build the thing.</text></transcript>',
                encoding="utf-8",
            )
            self.assertEqual(parse_srv1(path), "Hello & welcome. Build the thing.")

    def test_duration_and_low_value_filter(self):
        self.assertEqual(parse_duration_seconds("1:02:03"), 3723)
        self.assertEqual(parse_duration_seconds(""), None)
        self.assertFalse(
            useful_candidate(
                {"title": "Best Compilation", "length": "10:00"}
            )
        )
        self.assertFalse(
            useful_candidate(
                {"title": "Tiny lesson", "length": "0:45"}
            )
        )
        self.assertTrue(
            useful_candidate(
                {"title": "Deep lesson", "length": "10:00"}
            )
        )

    def test_discovers_primary_and_profile_databases(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            primary = home / ".hermes" / "state.db"
            profile = home / ".hermes" / "agent-profiles" / "research" / "state.db"
            primary.parent.mkdir(parents=True)
            profile.parent.mkdir(parents=True)
            primary.touch()
            profile.touch()
            self.assertEqual(database_paths(home), [primary, profile])

    def test_detects_only_the_managed_youtube_block(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hosts"
            path.write_text(
                "# BEGIN VAULTY MANAGED BLOCK\n"
                "0.0.0.0 youtube.com\n"
                "# END VAULTY MANAGED BLOCK\n",
                encoding="utf-8",
            )
            self.assertTrue(youtube_blocked_by_vaulty(path))
            self.assertTrue(youtube_blocked_by_focusvault(path))
            path.write_text("0.0.0.0 youtube.com\n", encoding="utf-8")
            self.assertFalse(youtube_blocked_by_vaulty(path))

            path.write_text(
                "# BEGIN FOCUSVAULT MANAGED BLOCK\n"
                "0.0.0.0 youtube.com\n"
                "# END FOCUSVAULT MANAGED BLOCK\n",
                encoding="utf-8",
            )
            self.assertTrue(youtube_blocked_by_vaulty(path))


if __name__ == "__main__":
    unittest.main()
