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

# Sync dev.just with the template (symlink so future updates auto-apply)
sync:
    @ln -sf ~/.config/claude-devcontainer/dev.just {{ root }}/.devcontainer/dev.just && echo "dev.just symlinked to template — future updates auto-apply."

# Start the devcontainer (idempotent)
up:
    devcontainer up --workspace-folder {{ root }}

# Rebuild image (uses cache) and restart container
rebuild:
    devcontainer up --workspace-folder {{ root }} --remove-existing-container

# Rebuild image from scratch (no cache) and restart container
rebuild-full:
    devcontainer up --workspace-folder {{ root }} --remove-existing-container --build-no-cache

# Run Claude Code with permissions skipped (safe inside the sandbox).
# tmux -CC = iTerm2 control mode: native scrolling, native tabs, tmux is invisible.
# New iTerm2 tab (Cmd+T) = new parallel Claude session (via tmux-claude.conf).
# Session name = project folder; tab color = deterministic from the name, so the
# same project always gets the same color and different projects differ.
claude *args:
    #!/usr/bin/env bash
    set -euo pipefail
    proj=$(basename "{{ root }}")
    palette=(
        "255;140;0"   "0;180;180"   "160;100;220" "100;200;100"
        "80;140;240"  "230;100;150" "220;200;80"  "80;200;220"
        "220;80;80"   "160;220;60"  "220;80;200"  "100;180;240"
    )
    idx=$(printf '%s' "$proj" | cksum | awk '{print $1 % '"${#palette[@]}"'}')
    rgb="${palette[$idx]}"
    devcontainer exec --workspace-folder "{{ root }}" \
        tmux -CC -f /home/node/.tmux-claude.conf \
        new-session -s "$proj" -n "$proj" \
        -e "CLAUDE_TAB_RGB=$rgb" \
        "bash /home/node/.claude-launch.sh {{ args }}"

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

# Show sandbox status and firewall health
status:
    #!/usr/bin/env bash
    set -euo pipefail
    GREEN='\033[0;32m' RED='\033[0;31m' YELLOW='\033[1;33m'
    BOLD='\033[1m' DIM='\033[2m' NC='\033[0m'
    id=$(docker ps -aq --filter "label=devcontainer.local_folder={{ root }}")
    if [ -z "$id" ]; then
        printf "${YELLOW}Container:${NC} not found\n"
        printf "${DIM}Run 'just dev::up' to start.${NC}\n"
        exit 0
    fi
    state=$(docker inspect -f '{{ "{{" }}.State.Status{{ "}}" }}' "$id")
    if [ "$state" = "running" ]; then
        printf "${GREEN}Container:${NC} running ${DIM}(%s)${NC}\n" "$id"
    else
        printf "${YELLOW}Container:${NC} %s ${DIM}(%s)${NC}\n" "$state" "$id"
        exit 0
    fi
    ip_count=$(docker exec "$id" sudo ipset list allowed-domains 2>/dev/null | grep -cE "^[0-9]" || echo "0")
    printf "${GREEN}Firewall:${NC}  %s allowed IPs/CIDRs\n" "$ip_count"
    if docker exec "$id" curl -sf --connect-timeout 3 https://api.anthropic.com >/dev/null 2>&1; then
        printf "${GREEN}Network:${NC}   Anthropic API reachable\n"
    else
        printf "${RED}Network:${NC}   Anthropic API unreachable\n"
    fi

# Enable Playwright MCP (browser automation) for this project
playwright-on:
    #!/usr/bin/env bash
    f="{{ root }}/.mcp.json"
    entry='{"command":"npx","args":["@playwright/mcp","--headless"]}'
    if [ -f "$f" ]; then
        jq --argjson pw "$entry" '.mcpServers.playwright = $pw' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    else
        echo '{"mcpServers":{"playwright":'"$entry"'}}' | jq . > "$f"
    fi
    echo "Playwright MCP enabled — restart Claude to pick it up."

# Disable Playwright MCP for this project
playwright-off:
    #!/usr/bin/env bash
    f="{{ root }}/.mcp.json"
    if [ ! -f "$f" ]; then
        echo "No .mcp.json found."; exit 0
    fi
    jq 'del(.mcpServers.playwright)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    # Remove file if no servers remain
    if [ "$(jq '.mcpServers | length' "$f")" = "0" ]; then
        rm "$f"
    fi
    echo "Playwright MCP disabled — restart Claude to pick it up."

# Tail container logs (-f to follow)
logs *args:
    #!/usr/bin/env bash
    id=$(docker ps -aq --filter "label=devcontainer.local_folder={{ root }}")
    if [ -z "$id" ]; then
        echo "No sandbox found. Run 'just dev::up' to start."
        exit 1
    fi
    docker logs {{ args }} "$id"
