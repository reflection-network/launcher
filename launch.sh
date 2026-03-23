# Launcher: monitors the agent repo, rebuilds and restarts on new commits.
#
# Usage:
#   nix run .#launch [-- --poll-interval 30]
#
# Environment variables:
#   REPO_DIR         — path to agent repo (default: current directory)
#   CONTAINER_NAME   — docker container name (default: repo directory name)
#   ENV_FILE         — path to .env (default: $REPO_DIR/.env)
#   CREDENTIALS_FILE — path to credentials (default: $REPO_DIR/.credentials.json)
#   CONTAINER_MEMORY — container memory limit (default: 4g)
#   POLL_INTERVAL    — seconds between checks (default: 30)

REPO_DIR="${REPO_DIR:-$(pwd)}"
CONTAINER_NAME="${CONTAINER_NAME:-$(basename "$REPO_DIR")}"
ENV_FILE="${ENV_FILE:-$REPO_DIR/.env}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$REPO_DIR/.credentials.json}"
CONTAINER_MEMORY="${CONTAINER_MEMORY:-4g}"
POLL_INTERVAL="${POLL_INTERVAL:-30}"
IMAGE_NAME=""
CURRENT_HASH=""

log() { echo "[$(date -Iseconds)] $*"; }

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --poll-interval) POLL_INTERVAL="$2"; shift 2 ;;
    *) log "Unknown arg: $1"; exit 1 ;;
  esac
done

get_remote_hash() {
  git -C "$REPO_DIR" fetch origin --quiet 2>/dev/null
  git -C "$REPO_DIR" rev-parse origin/master 2>/dev/null
}

get_local_hash() {
  git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null
}

# Load a Docker image and capture its name from docker load output.
# Sets IMAGE_NAME as a side effect.
load_image() {
  local result_path="$1"
  local output
  output=$(docker load < "$result_path")
  log "$output"
  IMAGE_NAME=$(echo "$output" | grep 'Loaded image:' | sed 's/Loaded image: //' | cut -d: -f1)
}

build_image() {
  log "Building Docker image..."
  nix --extra-experimental-features "nix-command flakes" \
    build "$REPO_DIR#packages.x86_64-linux.docker" -o "$REPO_DIR/result"
  load_image "$REPO_DIR/result"
  log "Build complete."
}

# Build from a specific remote commit without touching the working copy.
# Returns 0 if build succeeds, 1 otherwise.
try_build() {
  local commit="$1"
  local worktree="$REPO_DIR/.worktree-build"

  rm -rf "$worktree"
  git -C "$REPO_DIR" worktree add --detach "$worktree" "$commit" 2>/dev/null || return 1

  log "Building $commit in worktree..."
  if nix --extra-experimental-features "nix-command flakes" \
       build "$worktree#packages.x86_64-linux.docker" -o "$worktree/result"; then
    load_image "$worktree/result"
    git -C "$REPO_DIR" worktree remove --force "$worktree" 2>/dev/null
    return 0
  else
    log "Build failed at $commit"
    git -C "$REPO_DIR" worktree remove --force "$worktree" 2>/dev/null
    return 1
  fi
}

stop_container() {
  if docker ps -q --filter "name=^${CONTAINER_NAME}$" | grep -q .; then
    log "Stopping container $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    log "Container stopped."
  fi
}

start_container() {
  log "Starting container $CONTAINER_NAME..."
  docker run -d \
    --name "$CONTAINER_NAME" \
    --env-file "$ENV_FILE" \
    --memory "$CONTAINER_MEMORY" \
    -v "${CONTAINER_NAME}-home:/home/agent" \
    -v "$CREDENTIALS_FILE:/home/agent/.claude/.credentials.json" \
    "${IMAGE_NAME}:latest"
  log "Container started."
}

deploy() {
  local new_hash="$1"
  log "Deploying $new_hash..."

  if ! try_build "$new_hash"; then
    log "Deploy aborted — working copy unchanged, old container kept"
    return 1
  fi

  # Build succeeded — fast-forward working copy
  git -C "$REPO_DIR" pull --ff-only origin master

  stop_container
  start_container

  CURRENT_HASH="$new_hash"
  log "Deploy complete. Running $CURRENT_HASH"
}

# --- Main ---

trap 'log "Shutting down..."; stop_container; exit 0' INT TERM

CURRENT_HASH="$(get_local_hash)"

log "Launcher started"
log "  repo:      $REPO_DIR"
log "  container: $CONTAINER_NAME"
log "  interval:  ${POLL_INTERVAL}s"
log "  commit:    $CURRENT_HASH"

# Initial deploy from current working copy
log "Initial deploy..."
if build_image; then
  stop_container
  start_container
else
  log "ERROR: initial build failed"
  if docker ps -q --filter "name=^${CONTAINER_NAME}$" | grep -q .; then
    log "Existing container still running, keeping it"
  else
    log "No container running and build failed — waiting for a fix commit"
  fi
fi

# Poll loop
while true; do
  sleep "$POLL_INTERVAL"

  remote_hash="$(get_remote_hash)" || continue
  if [[ "$remote_hash" != "$CURRENT_HASH" ]]; then
    log "New commit detected: $CURRENT_HASH -> $remote_hash"
    deploy "$remote_hash" || true
  fi
done
