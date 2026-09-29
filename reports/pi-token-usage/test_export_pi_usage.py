"""Regression tests for the Pi usage export layout."""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("export_pi_usage.py")
SPEC = importlib.util.spec_from_file_location("export_pi_usage", SCRIPT)
export = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(export)


class ExportLayoutTests(unittest.TestCase):
    def write_session(self, root: Path, filename: str, session_id: str) -> Path:
        path = root / filename
        records = [
            {"type": "session", "id": session_id, "timestamp": "2026-09-29T00:00:00Z", "cwd": "test"},
            {
                "type": "message",
                "timestamp": "2026-09-29T00:00:01Z",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "done"}],
                    "usage": {"input": 2, "output": 3, "totalTokens": 5},
                },
            },
        ]
        path.write_text("\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8")
        return path

    def test_primary_and_other_logs_use_their_own_session_ids(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = self.write_session(root, "timestamp_first.jsonl", "first-id")
            second = self.write_session(root, "timestamp_second.jsonl", "second-id")
            output = root / "output"
            with patch.object(export, "session_files", return_value=[first, second]), patch.object(
                sys, "argv", [str(SCRIPT), "--session", str(first), "--out", str(output), "--all-logs"]
            ):
                self.assertEqual(export.main(), 0)

            first_dir = output / "first-id"
            self.assertEqual(json.loads((first_dir / "usage.json").read_text(encoding="utf-8"))["session_id"], "first-id")
            for name in ("usage.md", "usage-per-call.csv", "all-sessions.md"):
                self.assertTrue((first_dir / name).is_file(), name)
            self.assertTrue((first_dir / "logs" / "session-first-id.jsonl").is_file())
            self.assertTrue((first_dir / "logs" / "session-first-id.md").is_file())
            self.assertTrue((output / "second-id" / "logs" / "session-second-id.jsonl").is_file())
            self.assertTrue((output / "second-id" / "logs" / "session-second-id.md").is_file())
            self.assertFalse((output / "usage.md").exists())
            self.assertFalse((first_dir / "logs" / "session-second-id.jsonl").exists())


if __name__ == "__main__":
    unittest.main()
