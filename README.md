# launcher

Dev launcher that polls git, rebuilds, and restarts agent containers on new commits.

## What it does

The launcher watches an agent capsule's git remote. When a new commit appears on `master`, it builds the Docker image in an isolated git worktree, loads it, and restarts the container. If the build fails, the old container keeps running — the working copy is never modified with broken code.

## Usage

```bash
cd my-agent-capsule
nix run github:reflection-network/launcher
```

The launcher builds from the current directory on startup, then polls every 30 seconds.

## Configuration

All via environment variables (all optional):

| Variable | Default | Description |
|----------|---------|-------------|
| `REPO_DIR` | `$(pwd)` | Path to agent capsule repo |
| `CONTAINER_NAME` | `agent` | Docker container name |
| `ENV_FILE` | `$REPO_DIR/.env` | Env file passed to `docker run` |
| `CREDENTIALS_FILE` | `~/.claude/.credentials.json` | Claude credentials to mount |
| `POLL_INTERVAL` | `30` | Seconds between git checks |

## Architecture

The deploy cycle on a new commit:

1. `git fetch` — download new commits without modifying working copy
2. `git worktree add .worktree-build <hash>` — isolated checkout of the new commit
3. `nix build` in the worktree — build Docker image
4. If build **fails** → remove worktree, log error, old container keeps running
5. If build **succeeds** → `docker load`, remove worktree, `git pull --ff-only`, restart container

Key invariant: the working copy always contains the last successfully built code. Launcher restart always produces a working build.

## The flake

The launcher is a `writeShellApplication` wrapping ~150 lines of bash. Nix provides `git`, `docker`, `nix`, and `coreutils` via `runtimeInputs` — no host dependencies beyond Nix itself.

## Documentation

- [Dev launcher](https://docs.reflection.network/launcher) — full documentation with examples and limitations
