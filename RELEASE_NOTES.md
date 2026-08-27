# GateTree - next release

## Open panes, grouped by service

- Replaced the mixed top tabs with a compact **Open panes** rail on the right.
- Opening the rail overlays the active SSH or RDP session; it does not resize
  or interrupt the live terminal.
- Panes are grouped with coloured icons: **SSH**, **RDP**, **Thanos**,
  **Grafana**, **Confluence**, **Jira**, **SCM**, **Dashboards** and **Web**.
- Added live search in Open panes. Search by connection name, host, service,
  bookmark name, URL or tag.
- A web pane is assigned to one primary service group, avoiding duplicate
  entries when a URL contains more than one technology name.
- Choosing a pane, pressing Escape or using the collapse button hides the
  expanded rail again.

## Connection workflow improvements

- SSH connection ordering can be changed with drag and drop in the tree.
- International keyboard Option characters, including the Hungarian pipe
  character, are passed through to embedded SSH sessions.
