# GateTree 0.4.4

## Notes persistence fix

- Fixed a race condition that could leave recently changed encrypted notes out
  of the workspace file when a prior save was still running.
- Pending changes now trigger a follow-up save, so closing and reopening the
  laptop cannot reload an older workspace version over current notes.
