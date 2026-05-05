`symlink-watch.sh` polls the repository for symlink changes and writes a process snapshot when they change.

Current behavior:
- snapshots all symlinks under the repo
- logs additions, removals, and target changes
- excludes heavy infrastructure paths such as `.git`, `.vscode-server`, and `node_modules`

Logs:
- `/var/log/supervisor/symlink-watch.log`
- `/var/log/supervisor/symlink-watch-error.log`
