# GateTree 0.4.0

## Encrypted Notes

- Added a built-in **Notes** workspace above Applications in the sidebar.
- Notes are stored only inside the encrypted workspace payload. There is no
  separate plaintext note file or autosave location.
- Added Root notes and one-level note folders. Drag notes between folders or
  back to Root notes; deleting a folder safely moves its notes to the root.
- The main search also searches note titles and note contents.
- Notes require an encrypted workspace. Selecting Notes in a plaintext
  workspace now opens the encryption flow directly.

## Workspace polish

- Connections and Applications are collapsible, left-aligned sidebar sections.
- Master-password setup and unlock submit with one press of Return.
- Password validation is immediate: eight characters are required and the
  confirmation must match before encryption can start.
