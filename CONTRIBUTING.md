# working on OmaJournal

edit the code here, then copy it into the plugins folder and restart the shell (the panel only picks up QML changes on a restart):

```bash
scripts/dev-install.sh
omarchy restart shell
```

the helper works from a terminal too. point it at a test vault so your real notes stay put:

```bash
python3 -B helpers/omajournalctl --vault /path/to/test-vault month 2026-10
python3 -B helpers/omajournalctl --vault /path/to/test-vault day 2026-10-19
echo "buy milk" | python3 -B helpers/omajournalctl --vault /path/to/test-vault add 2026-10-19 <hash from day>
```

`tests/test_helper.py` runs every command against a throwaway vault:

```bash
python3 -B tests/test_helper.py
```
