#!/usr/bin/env python3
"""Runs every helper command against a throwaway vault."""
import hashlib
import json
import os
import subprocess
import sys
import tempfile

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "helpers", "omajournalctl")


def run(vault, *args, stdin=""):
    out = subprocess.run([sys.executable, "-B", "-I", HELPER, "--vault", vault, *args],
                         input=stdin, capture_output=True, text=True, timeout=10)
    return json.loads(out.stdout)


def note(vault, rel):
    with open(os.path.join(vault, rel), encoding="utf-8") as stream:
        return stream.read()


def main():
    with tempfile.TemporaryDirectory() as vault:
        os.makedirs(os.path.join(vault, ".obsidian"))
        os.makedirs(os.path.join(vault, "Templates"))
        with open(os.path.join(vault, ".obsidian", "daily-notes.json"), "w") as stream:
            json.dump({"folder": "Daily", "format": "YYYY/MM - MMMM/DD - dddd", "template": "Templates/Day"}, stream)
        with open(os.path.join(vault, "Templates", "Day.md"), "w") as stream:
            stream.write("# {{date:dddd, MMMM D}}\n\n## To do\n\n- [ ] \n\n## Journal\n\n## Next\n")

        day = run(vault, "day", "2026-10-19")
        assert day["ok"] and not day["exists"], day
        rel = day["file"]
        assert rel == "Daily/2026/10 - October/19 - Monday.md", rel

        made = run(vault, "create", "2026-10-19")
        assert made["exists"] and "# Monday, October 19" in note(vault, rel)
        assert oct(os.stat(os.path.join(vault, rel)).st_mode & 0o777) == "0o600"

        added = run(vault, "add", "2026-10-19", made["hash"], stdin="buy milk\n")
        assert [t["text"] for t in added["todoList"]] == ["buy milk"], added
        added = run(vault, "add", "2026-10-19", added["hash"], stdin="call mom\n")
        noted = run(vault, "note", "2026-10-19", added["hash"], stdin="nice day\n")
        assert noted["journal"] == ["nice day"], noted

        line = noted["todoList"][0]["line"]
        ticked = run(vault, "toggle", "2026-10-19", str(line), noted["hash"])
        assert ticked["todoList"][0]["done"] and ticked["done"] == 1, ticked

        stale = run(vault, "toggle", "2026-10-19", str(line), noted["hash"])
        assert not stale["ok"], "an old hash must be refused"

        text = note(vault, rel)
        assert text.index("buy milk") < text.index("call mom") < text.index("## Journal") < text.index("nice day") < text.index("## Next"), text

        month = run(vault, "month", "2026-10")
        assert month["days"]["2026-10-19"]["dots"] == 1 and month["days"]["2026-10-19"]["openTasks"], month

        # A note without a To do section gets one at the top.
        bare = os.path.join(vault, "Daily/2026/10 - October/18 - Sunday.md")
        with open(bare, "w") as stream:
            stream.write("## Journal\n\n- old\n\n## Next\n\n- later\n")
        digest = hashlib.sha256(open(bare, "rb").read()).hexdigest()
        run(vault, "add", "2026-10-18", digest, stdin="top task\n")
        assert note(vault, "Daily/2026/10 - October/18 - Sunday.md").startswith("## To do\n\n- [ ] top task\n"), note(vault, "Daily/2026/10 - October/18 - Sunday.md")

        leftovers = [name for _, _, files in os.walk(vault) for name in files if name.startswith(".omajournal-")]
        assert not leftovers, leftovers
    print("all helper tests passed")


if __name__ == "__main__":
    main()
