import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SKILL = Path(__file__).resolve().parents[1]
GATE = SKILL / "hooks" / "ste-gate.py"
INJECT = SKILL / "hooks" / "ste-inject.sh"

SLOP = ("Great question! We have leveraged a robust, cutting-edge solution to seamlessly "
        "facilitate the deployment process; furthermore, the file is read by the parser "
        "prior to initialization; it is important to note that this is powerful. "
        "Additionally, we have utilized a world-class, next-generation framework; it "
        "should be noted that the configuration has been optimized by the team, and the "
        "results have been demonstrated. Moreover, it's a revolutionary, effortless "
        "approach that we've commenced. Hope this helps! Let me know if you need anything else.")

WARN = {"score": 3.1, "limit": 2.5, "top": ["banned 3"], "shape_total": 0,
        "shape_top": [], "longest_sentence_words": 31}


def make_home(test):
    # The hooks keep state under ~/.claude/ste-gate and find the linter under
    # ~/.claude/skills. A temporary HOME keeps each test away from a real session.
    home = tempfile.mkdtemp()
    test.addCleanup(shutil.rmtree, home)
    skills = Path(home) / ".claude" / "skills"
    skills.mkdir(parents=True)
    (skills / "ste-writing").symlink_to(SKILL)
    # An asdf shim for jq looks for .tool-versions up to HOME. Without it, jq
    # fails when the tests run outside a folder that has one.
    versions = Path.home() / ".tool-versions"
    if versions.exists():
        (Path(home) / ".tool-versions").symlink_to(versions)
    return home


def run_hook(command, payload, home, project=None):
    env = dict(os.environ, HOME=home)
    env.pop("CLAUDE_PROJECT_DIR", None)
    if project:
        env["CLAUDE_PROJECT_DIR"] = project
    proc = subprocess.run(command, input=json.dumps(payload), capture_output=True,
                          text=True, timeout=30, env=env)
    out = proc.stdout.strip()
    return json.loads(out) if out else None


def gate(payload, home):
    return run_hook([sys.executable, str(GATE)], payload, home)


def inject(payload, home, project=None):
    return run_hook(["bash", str(INJECT)], payload, home, project)


def write_transcript(home, records):
    path = os.path.join(home, "transcript.jsonl")
    with open(path, "w", encoding="utf-8") as fh:
        for rec in records:
            fh.write(json.dumps(rec) + "\n")
    return path


def user_turn(text):
    return {"type": "user", "message": {"content": text}}


def assistant_turn(text):
    return {"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}


def warn_path(home, session):
    key = subprocess.run(["shasum"], input=session, capture_output=True,
                         text=True).stdout[:16]
    state = Path(home) / ".claude" / "ste-gate"
    state.mkdir(parents=True, exist_ok=True)
    return state / "{}.warn.json".format(key)


class StopGateTests(unittest.TestCase):
    def setUp(self):
        self.home = make_home(self)

    def test_a_slop_reply_not_yet_in_the_transcript_is_blocked(self):
        transcript = write_transcript(self.home, [])
        out = gate({"session_id": "s1", "transcript_path": transcript,
                    "last_assistant_message": SLOP}, self.home)
        self.assertIsNotNone(out)
        self.assertEqual(out["decision"], "block")

    def test_a_turn_that_ends_with_no_text_does_not_score_the_reply_before(self):
        transcript = write_transcript(self.home, [
            user_turn("Explain the deploy."), assistant_turn(SLOP), user_turn("Now run it.")])
        out = gate({"session_id": "s2", "transcript_path": transcript,
                    "last_assistant_message": ""}, self.home)
        self.assertIsNone(out)

    def test_a_block_shows_no_score_on_the_screen(self):
        transcript = write_transcript(self.home, [user_turn("Explain the deploy."),
                                                  assistant_turn(SLOP)])
        out = gate({"session_id": "s3", "transcript_path": transcript}, self.home)
        self.assertEqual(out["decision"], "block")
        self.assertIn("reason", out)
        self.assertNotIn("systemMessage", out)


class GateToInjectTests(unittest.TestCase):
    def setUp(self):
        self.home = make_home(self)

    def test_a_slop_rewrite_after_a_block_gets_its_score_on_the_next_prompt(self):
        transcript = write_transcript(self.home, [user_turn("Explain the deploy."),
                                                  assistant_turn(SLOP)])
        first = gate({"session_id": "s8", "transcript_path": transcript}, self.home)
        self.assertEqual(first["decision"], "block")
        second = gate({"session_id": "s8", "transcript_path": transcript,
                       "stop_hook_active": True, "last_assistant_message": SLOP}, self.home)
        self.assertIsNone(second)
        out = inject({"session_id": "s8", "hook_event_name": "UserPromptSubmit",
                      "prompt": "Hi"}, self.home)
        self.assertIn("<ste-writing-feedback>", out["hookSpecificOutput"]["additionalContext"])


class InjectTests(unittest.TestCase):
    def setUp(self):
        self.home = make_home(self)

    def test_a_new_session_gets_the_rule_card(self):
        out = inject({"session_id": "s4", "hook_event_name": "SessionStart",
                      "source": "startup"}, self.home)
        self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "SessionStart")
        self.assertIn("<ste-writing-standing-rule>",
                      out["hookSpecificOutput"]["additionalContext"])

    def test_a_prompt_after_a_clean_reply_gets_nothing(self):
        out = inject({"session_id": "s5", "hook_event_name": "UserPromptSubmit",
                      "prompt": "Hi"}, self.home)
        self.assertIsNone(out)

    def test_a_prompt_after_a_warned_reply_gets_the_card_and_the_score(self):
        warn = warn_path(self.home, "s6")
        warn.write_text(json.dumps(WARN), encoding="utf-8")
        out = inject({"session_id": "s6", "hook_event_name": "UserPromptSubmit",
                      "prompt": "Hi"}, self.home)
        context = out["hookSpecificOutput"]["additionalContext"]
        self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "UserPromptSubmit")
        self.assertIn("<ste-writing-standing-rule>", context)
        self.assertIn("scored 3.1 violations", context)
        self.assertFalse(warn.exists())

    def test_a_repo_with_its_own_ste_hooks_gets_no_second_card(self):
        project = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, project)
        (Path(project) / ".claude" / "skills" / "ste" / "hooks").mkdir(parents=True)
        out = inject({"session_id": "s7", "hook_event_name": "SessionStart",
                      "source": "startup"}, self.home, project)
        self.assertIsNone(out)


if __name__ == "__main__":
    unittest.main()
