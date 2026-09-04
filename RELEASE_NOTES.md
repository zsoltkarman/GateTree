# GateTree 0.4.6

## SSH terminal compatibility

- SSH sessions now advertise the broadly available `xterm` terminal type.
  This fixes `watch` and other curses-based tools on minimal Oracle Linux
  hosts that do not include the `xterm-256color` terminfo entry.
