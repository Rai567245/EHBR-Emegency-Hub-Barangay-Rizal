# EHBR Development Progress Logs

This folder documents daily development work for the Emergency Hub Barangay System (EHBR).

## Files

- [`master-progress.md`](master-progress.md) — high-level status of screens, features, and technical work.
- [`daily/`](daily/) — one detailed report per development day.

## Daily workflow

1. Copy `daily/YYYY-MM-DD-template.md` and rename it using the date, for example `2026-10-30.md`.
2. Record only changes that were actually made.
3. Include relevant screen/frame names, code file paths, tests, and Git commit or pull request links.
4. Mark unverified behavior as `Not tested`; do not mark it as completed merely because code was changed.
5. Update `master-progress.md` when a screen, feature, or task changes status.
6. Commit the log with a descriptive message, for example: `docs: add EHBR progress log for 2026-10-30`.

## Status vocabulary

- `Not Started` — work has not begun.
- `In Progress` — work is underway.
- `In Review` — awaiting review or verification.
- `Completed` — acceptance criteria have been met and verified.
- `Blocked` — progress depends on an unresolved issue.
- `Not Tested` — implementation exists, but verification has not been performed.

## Security note

Do not put API keys, passwords, tokens, private credentials, personal resident data, or sensitive production data in these reports. Link to a safe code location or commit instead of copying secrets or private values.
