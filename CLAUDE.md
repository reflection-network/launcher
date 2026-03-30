# launcher

Dev launcher that polls a git remote and rebuilds/restarts agent containers on new commits. Uses git worktrees for safe, isolated builds.

## Stack

Nix, bash (~150 lines).

## Key invariant

The working copy always contains the last successful build. If a build fails in the worktree, the old container keeps running.

## How it works

1. Polls `git fetch origin` every N seconds
2. On new commit: creates git worktree, builds Docker image in isolation
3. Build fails → removes worktree, logs error, old container keeps running
4. Build succeeds → loads image, `git pull --ff-only` in working copy, restarts container

## Environment variables

All optional with sensible defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `REPO_DIR` | `$(pwd)` | Path to the capsule repo |
| `CONTAINER_NAME` | basename of REPO_DIR | Docker container name |
| `ENV_FILE` | `$REPO_DIR/.env` | Env file for container secrets |
| `CREDENTIALS_FILE` | `$REPO_DIR/.credentials.json` | Claude credentials file |
| `CONTAINER_MEMORY` | `4g` | Docker memory limit |
| `POLL_INTERVAL` | `30` | Seconds between git fetches |
| `WEB_PORT` | unset | Host port mapped to container 8080 |

## Docker run

Mounts: agent-home volume, credentials file. Uses `--env-file` for secrets, `--memory` for limits. Conditionally adds `-p` for `WEB_PORT`.
