# Release checks — 1.0.0

12 October 2026. Local release preparation, not a security audit.

- 32 Python tests pass: 28 backend cases and four release/controller checks.
- Seven JavaScript visibility checks pass.
- `omarchy plugin validate .` passes against installed Omarchy Quattro tooling.
- Absolute developer-home path removed from the bar bridge; helpers resolve beside the installed QML. Controller relocation tested with a path containing spaces.
- Packaged panel loaded in Quickshell, reported empty/collapsed with no backend error, and exited through its exact configuration IPC. Quickshell's scanner reports missing qs.Commons/qs.Ui for the sibling bar component in standalone panel mode; those imports are provided by the main shell when the bar widget is hosted there. They did not prevent panel loading.
- Original prototype's panel/backend behaviour is retained. Earlier local Shibumi catalogue test passed with 79 entries after replacing the installed development symlink with regular files; Lee confirmed the icon controls work. No Shibumi source patches are included.
- Release preparation did not move or close user application windows or replace the working prototype installation.

The tests use synthetic windows/mock dispatch. Full theme, multi-monitor, fullscreen and fresh-login behaviour is not exhaustively tested. New-user enablement on every custom bar is not claimed. The approved preview is screenshot-based composed artwork with illustrative parked states.

Native installer and remover passed in a Bubblewrap-isolated home directory against the public repository. Unmodified `omarchy-plugin-add ... --yes` cloned and validated the package as regular files; unmodified `omarchy-plugin-remove ... --yes` removed that test checkout. Shell list/rescan IPC was stubbed, so this verifies filesystem/manifest lifecycle, not actual bar enablement or every custom bar. The real home and installed prototype were not mutated; its widget still byte-matches development source. No rollback restoration was performed.
