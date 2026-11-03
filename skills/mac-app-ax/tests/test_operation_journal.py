import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "templates"))
from operation_journal import OperationJournal  # noqa: E402


class FakeApp:
    def __init__(self, applies=True, result=None, raises=False):
        self.rows = 10
        self.calls = 0
        self.applies = applies
        self.result = result or {"status": "dispatch_result_unknown", "axResult": -25200, "dispatchAttempted": True}
        self.raises = raises

    def dispatch(self):
        self.calls += 1
        if self.applies:
            self.rows += 1
        if self.raises:
            raise TimeoutError
        return self.result


class OperationJournalTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.journal = OperationJournal(Path(self.tmp.name) / "ops")

    def tearDown(self):
        self.tmp.cleanup()

    def run_once(self, app, operation_id="op-1", target=None, wait=0.2):
        return self.journal.run(operation_id, target or {"window": "w", "text": "hi"},
                                baseline=lambda: app.rows, dispatch=app.dispatch,
                                confirm=lambda base: app.rows == base + 1, wait_seconds=wait)

    def test_error_from_press_is_confirmed_by_observation_not_retried(self):
        app = FakeApp()
        result = self.run_once(app)
        self.assertEqual(result["status"], "observed")
        self.assertEqual(app.calls, 1)

    def test_same_id_never_dispatches_twice(self):
        app = FakeApp()
        self.run_once(app)
        again = self.run_once(app)
        self.assertEqual(again["status"], "observed")
        self.assertTrue(again["deduplicated"])
        self.assertEqual(again["nativeCalls"], 0)
        self.assertEqual(app.calls, 1)

    def test_unobserved_change_is_unknown_and_still_not_retried(self):
        app = FakeApp(applies=False)
        first = self.run_once(app)
        self.assertEqual(first["status"], "outcome_unknown")
        again = self.run_once(app)
        self.assertEqual(again["status"], "outcome_unknown")
        self.assertEqual(app.calls, 1)

    def test_lost_response_keeps_dispatching_record(self):
        app = FakeApp(raises=True)
        first = self.run_once(app)
        self.assertEqual(first["status"], "observed")
        self.assertEqual(app.calls, 1)

    def test_blocked_before_dispatch(self):
        app = FakeApp(applies=False, result={"status": "blocked", "reason": "existing_draft_preserved",
                                             "dispatchAttempted": False})
        result = self.run_once(app)
        self.assertEqual(result["status"], "blocked")
        self.assertEqual(result["reason"], "existing_draft_preserved")

    def test_reusing_id_for_other_content_is_rejected(self):
        app = FakeApp()
        self.run_once(app)
        with self.assertRaises(ValueError):
            self.run_once(app, target={"window": "w", "text": "different"})

    def test_result_lookup_never_dispatches(self):
        app = FakeApp(applies=False)
        self.run_once(app)
        app.rows += 1  # the change shows up later
        looked = self.journal.result("op-1", confirm=lambda base: app.rows == base + 1)
        self.assertEqual(looked["status"], "observed")
        self.assertEqual(app.calls, 1)

    def test_record_holds_no_plain_text(self):
        app = FakeApp()
        self.run_once(app, target={"window": "w", "text": "secret words"})
        stored = "".join(p.read_text() for p in (Path(self.tmp.name) / "ops").glob("*.json"))
        self.assertNotIn("secret words", stored)

    def test_invalid_id(self):
        with self.assertRaises(ValueError):
            self.run_once(FakeApp(), operation_id="has space")


if __name__ == "__main__":
    unittest.main()
