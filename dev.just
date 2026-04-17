# Claude Code sandbox module
# Usage: add `mod dev '.devcontainer/dev.just'` to your project's justfile.

root := justfile_directory()

# Ensure Colima (the Docker runtime) is running. Silent when already up; prints a
# one-liner with expected latency when cold-starting so the user knows why the
# next 15–30s are idle. Used as a dependency for every recipe that touches Docker.
_ensure-colima:
    #!/usr/bin/env bash
    set -euo pipefail
    if colima status &>/dev/null 2>&1; then
        exit 0
    fi
    YELLOW='\033[1;33m' DIM='\033[2m' NC='\033[0m'
    printf "${YELLOW}Colima isn't running${NC} — starting it now ${DIM}(~15–30s cold start, then stays warm)${NC}\n"
    colima start

# Verify and repair: check tools, start colima, rebuild image if pruned
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    ok=true
    for tool in docker devcontainer colima; do
        if command -v "$tool" &>/dev/null; then
            echo "✓ $tool"
        else
            echo "✗ $tool — run ~/.config/claude-devcontainer/install.sh"
            ok=false
        fi
    done
    if colima status &>/dev/null 2>&1; then
        echo "✓ Colima running"
    else
        echo "Starting Colima..."
        colima start
    fi
    if docker image inspect claude-sandbox &>/dev/null 2>&1; then
        echo "✓ claude-sandbox image"
    else
        echo "Rebuilding sandbox image..."
        docker build -t claude-sandbox ~/.config/claude-devcontainer
    fi
    if [ "$ok" = false ]; then
        echo "Some tools are missing — re-run install.sh."
        exit 1
    fi
    echo "All good."

# Start the devcontainer (idempotent)
up: _ensure-colima
    devcontainer up --workspace-folder {{ root }}

# Rebuild image (uses cache) and restart container; pass --build-no-cache for a full rebuild
rebuild *args: _ensure-colima
    devcontainer up --workspace-folder {{ root }} --remove-existing-container {{ args }}

# Run Claude Code (starts sandbox automatically; safe inside the sandbox)
claude *args: _ensure-colima
    #!/usr/bin/env bash
    set -euo pipefail
    # Auto-start the container if it's not running
    id=$(docker ps -q --filter "label=devcontainer.local_folder={{ root }}")
    if [ -z "$id" ]; then
        devcontainer up --workspace-folder "{{ root }}"
    fi
    # iTerm2 gets the tmux -CC path (native tabs + per-project tab color).
    # Every other terminal (cmux, Terminal.app, Alacritty, Kitty…) runs claude
    # directly — the host terminal handles tabs/panes; parallel sessions = open
    # another pane and re-run `just dev::claude` (devcontainer up is idempotent).
    if [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
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
    else
        devcontainer exec --workspace-folder "{{ root }}" \
            bash /home/node/.claude-launch.sh {{ args }}
    fi

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
        printf "${DIM}Run 'just dev::claude' to start.${NC}\n"
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
    if [ "$(jq '.mcpServers | length' "$f")" = "0" ]; then
        rm "$f"
    fi
    echo "Playwright MCP disabled — restart Claude to pick it up."

# Tail container logs (-f to follow)
logs *args:
    #!/usr/bin/env bash
    id=$(docker ps -aq --filter "label=devcontainer.local_folder={{ root }}")
    if [ -z "$id" ]; then
        echo "No sandbox found. Run 'just dev::claude' to start."
        exit 1
    fi
    docker logs {{ args }} "$id"
