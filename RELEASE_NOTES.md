# GateTree 0.4.5

## Embedded SSH terminal fixes

- Fixed cursor-key input in embedded SSH sessions. Up, down, left and right
  now send their standard VT100 sequences directly to the remote shell.
- SSH starts only once the terminal has a real allocated size, preventing
  history redraws from placing prompts and commands on the same line.
- Dragging to select now copies output while long-running commands, such as
  `podman pull`, are updating their progress display.
