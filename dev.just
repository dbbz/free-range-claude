# Claude Code sandbox module
# Usage: add `mod dev '.devcontainer/dev.just'` to your project's justfile.

root := justfile_directory()

# One-time setup: install docker CLI, devcontainer CLI, start colima, build image
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v docker &>/dev/null || { echo "Installing Docker CLI..."; brew install docker; }
    command -v devcontainer &>/dev/null || { echo "Installing devcontainer CLI..."; npm install -g @devcontainers/cli; }
    colima status &>/dev/null 2>&1 || { echo "Starting colima..."; colima start; }
    echo "Building sandbox image..."
    docker build -t claude-sandbox ~/.config/claude-devcontainer
    echo "Done! Run 'just dev::up' then 'just dev::claude'."

# Build (or rebuild) the sandbox image
build:
    docker build -t claude-sandbox ~/.config/claude-devcontainer

# Start the devcontainer (idempotent)
up:
    devcontainer up --workspace-folder {{ root }}

# Rebuild image (uses cache) and restart container
rebuild:
    devcontainer up --workspace-folder {{ root }} --remove-existing-container

# Rebuild image from scratch (no cache) and restart container
rebuild-full:
    devcontainer up --workspace-folder {{ root }} --remove-existing-container --build-no-cache

# Run Claude Code with permissions skipped (safe inside the sandbox)
# tmux -CC = iTerm2 control mode: native scrolling, native tabs, tmux is invisible
# New iTerm2 tab (Cmd+T) = new parallel Claude session (via tmux-claude.conf)
claude *args:
    devcontainer exec --workspace-folder {{ root }} tmux -CC -f /home/node/.tmux-claude.conf new-session claude --dangerously-skip-permissions {{ args }}

# Open a shell inside the devcontainer
shell:
    devcontainer exec --workspace-folder {{ root }} zsh

# Run any command inside the devcontainer
exec *args:
    devcontainer exec --workspace-folder {{ root }} {{ args }}

# Stop and remove the devcontainer
down:
    #!/usr/bin/env bash
    id=$(docker ps -aq --filter "label=devcontainer.local_folder={{ root }}")
    if [ -n "$id" ]; then
        docker rm -f "$id"
        echo "Sandbox removed."
    else
        echo "No sandbox found."
    fi
