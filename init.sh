#!/usr/bin/env bash
set -euo pipefail

# claude-devcontainer — project init wizard
# Run from any project directory to generate .devcontainer/

PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
DEVCONTAINER_DIR="$PROJECT_DIR/.devcontainer"
TEMPLATE_DIR="$(dirname "$(realpath "$0")")"

echo ""
echo "claude-devcontainer — Project Setup"
echo "===================================="
echo "Project: $PROJECT_NAME"
echo "Directory: $PROJECT_DIR"
echo ""

if [ -d "$DEVCONTAINER_DIR" ]; then
    read -rp ".devcontainer/ already exists. Overwrite? [y/N] " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# --- Question 1: Runtimes ---

echo "1. Extra runtimes"
echo "   The base image includes Node.js 20, git, zsh, and Claude Code."
echo "   Select additional runtimes (comma-separated, or Enter for none):"
echo ""
echo "   [1] Python 3 + uv"
echo "   [2] Rust (stable)"
echo "   [3] Go"
echo ""
read -rp "   Selection: " runtimes_input

RUNTIMES=()
if [ -n "$runtimes_input" ]; then
    IFS=',' read -ra selections <<< "$runtimes_input"
    for sel in "${selections[@]}"; do
        sel=$(echo "$sel" | xargs)
        case "$sel" in
            1) RUNTIMES+=("python") ;;
            2) RUNTIMES+=("rust") ;;
            3) RUNTIMES+=("go") ;;
            *) echo "   Skipping unknown option: $sel" ;;
        esac
    done
fi

# --- Auto-add package registries for selected runtimes ---

RUNTIME_HOSTS=()
for runtime in "${RUNTIMES[@]}"; do
    case "$runtime" in
        python)
            RUNTIME_HOSTS+=("pypi.org" "files.pythonhosted.org")
            echo "   -> Will allow pypi.org, files.pythonhosted.org"
            ;;
        rust)
            RUNTIME_HOSTS+=("crates.io" "static.crates.io" "index.crates.io")
            echo "   -> Will allow crates.io, static.crates.io, index.crates.io"
            ;;
        go)
            RUNTIME_HOSTS+=("proxy.golang.org" "sum.golang.org" "storage.googleapis.com")
            echo "   -> Will allow proxy.golang.org, sum.golang.org, storage.googleapis.com"
            ;;
    esac
done

# --- Question 2: Extra allowed hosts ---

echo ""
echo "2. Extra allowed network hosts"
echo "   The firewall allows: Anthropic API, GitHub, npm, Sentry, VS Code."
if [ ${#RUNTIME_HOSTS[@]} -gt 0 ]; then
    echo "   Package registries for selected runtimes will be added automatically."
fi
echo "   Add more domains, IPs, or CIDR ranges (comma-separated, or Enter for none)."
echo "   Examples: registry.mycompany.com, 100.64.0.0/10, 10.0.1.50"
echo ""
read -rp "   Extra: " extra_hosts_input

EXTRA_HOSTS=("${RUNTIME_HOSTS[@]}")
if [ -n "$extra_hosts_input" ]; then
    IFS=',' read -ra hosts <<< "$extra_hosts_input"
    for h in "${hosts[@]}"; do
        h=$(echo "$h" | xargs)
        [ -n "$h" ] && EXTRA_HOSTS+=("$h")
    done
fi

# --- Question 3: Static host entries ---

echo ""
echo "3. Static /etc/hosts entries"
echo "   For hosts without public DNS (e.g. Tailscale peers, internal services)."
echo "   Format: hostname:ip (comma-separated, or Enter for none)."
echo "   Example: myserver.ts.net:100.83.80.91"
echo ""
read -rp "   Entries: " add_hosts_input

ADD_HOSTS=()
ADD_HOST_IPS=()
if [ -n "$add_hosts_input" ]; then
    IFS=',' read -ra entries <<< "$add_hosts_input"
    for entry in "${entries[@]}"; do
        entry=$(echo "$entry" | xargs)
        if [[ "$entry" == *":"* ]]; then
            host="${entry%%:*}"
            ip="${entry#*:}"
            ADD_HOSTS+=("$host:$ip")
            ADD_HOST_IPS+=("$ip")
        else
            echo "   Skipping invalid entry (need host:ip): $entry"
        fi
    done
fi

# --- Generate files ---

echo ""
echo "Generating .devcontainer/..."
mkdir -p "$DEVCONTAINER_DIR"

# --- Generate Dockerfile (only if extra runtimes selected) ---

NEEDS_DOCKERFILE=false
if [ ${#RUNTIMES[@]} -gt 0 ]; then
    NEEDS_DOCKERFILE=true
    cat > "$DEVCONTAINER_DIR/Dockerfile" << 'DOCKERFILE_HEAD'
FROM claude-sandbox

USER root
DOCKERFILE_HEAD

    for runtime in "${RUNTIMES[@]}"; do
        case "$runtime" in
            python)
                cat >> "$DEVCONTAINER_DIR/Dockerfile" << 'EOF'

# Python 3 + uv
RUN apt-get update && apt-get install -y --no-install-recommends \
  python3 python3-pip python3-venv \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"
EOF
                ;;
            rust)
                cat >> "$DEVCONTAINER_DIR/Dockerfile" << 'EOF'

# Rust stable
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo
ENV PATH=$CARGO_HOME/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
  && chmod -R a+rw $RUSTUP_HOME $CARGO_HOME
EOF
                ;;
            go)
                cat >> "$DEVCONTAINER_DIR/Dockerfile" << 'EOF'

# Go
ARG GO_VERSION=1.23.2
RUN ARCH=$(dpkg --print-architecture) \
  && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH=$PATH:/usr/local/go/bin:/home/node/go/bin
EOF
                ;;
        esac
    done

    echo "" >> "$DEVCONTAINER_DIR/Dockerfile"
    echo "USER node" >> "$DEVCONTAINER_DIR/Dockerfile"
    echo "  -> Dockerfile (extends claude-sandbox with: ${RUNTIMES[*]})"
fi

# --- Generate devcontainer.json ---

# Build runArgs array
RUN_ARGS='    "--cap-add=NET_ADMIN",\n    "--cap-add=NET_RAW"'
for entry in "${ADD_HOSTS[@]}"; do
    RUN_ARGS="$RUN_ARGS"',\n    "--add-host='"$entry"'"'
done

# Build containerEnv
CONTAINER_ENV='    "NODE_OPTIONS": "--max-old-space-size=4096",
    "CLAUDE_CONFIG_DIR": "/home/node/.claude",
    "POWERLEVEL9K_DISABLE_GITSTATUS": "true"'

if [ ${#EXTRA_HOSTS[@]} -gt 0 ] || [ ${#ADD_HOST_IPS[@]} -gt 0 ]; then
    all_extra=()
    for h in "${EXTRA_HOSTS[@]}"; do all_extra+=("$h"); done
    # Add --add-host hostnames to the firewall allowlist too (need their IPs allowed)
    for ip in "${ADD_HOST_IPS[@]}"; do all_extra+=("$ip"); done
    extra_joined=$(IFS=','; echo "${all_extra[*]}")
    CONTAINER_ENV="$CONTAINER_ENV"',
    "EXTRA_ALLOWED_HOSTS": "'"$extra_joined"'"'
fi

# Image or build?
if [ "$NEEDS_DOCKERFILE" = true ]; then
    IMAGE_OR_BUILD='  "build": {\n    "dockerfile": "Dockerfile"\n  }'
else
    IMAGE_OR_BUILD='  "image": "claude-sandbox"'
fi

# Write devcontainer.json
printf '{
  "name": "claude-devcontainer",
'"$(echo -e "$IMAGE_OR_BUILD")"',
  "runArgs": [
'"$(echo -e "$RUN_ARGS")"'
  ],
  "remoteUser": "node",
  "updateRemoteUserUID": true,
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/node/.claude,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.claude,target=${localEnv:HOME}/.claude,type=bind,consistency=cached",
    "source=claude-history,target=/commandhistory,type=volume"
  ],
  "containerEnv": {
'"$CONTAINER_ENV"'
  },
  "postStartCommand": "sudo /usr/local/bin/init-firewall.sh",
  "waitFor": "postStartCommand"
}
' > "$DEVCONTAINER_DIR/devcontainer.json"

echo "  -> devcontainer.json"

# --- Copy dev.just and README ---

cp "$TEMPLATE_DIR/dev.just" "$DEVCONTAINER_DIR/dev.just" 2>/dev/null || true
cp "$TEMPLATE_DIR/project-readme.md" "$DEVCONTAINER_DIR/README.md" 2>/dev/null || true

if [ -f "$DEVCONTAINER_DIR/dev.just" ]; then
    echo "  -> dev.just"
fi
if [ -f "$DEVCONTAINER_DIR/README.md" ]; then
    echo "  -> README.md"
fi

# --- Update justfile ---

JUSTFILE="$PROJECT_DIR/justfile"
MOD_LINE="mod dev '.devcontainer/dev.just'"

if [ -f "$JUSTFILE" ]; then
    if grep -qF "$MOD_LINE" "$JUSTFILE"; then
        echo "  -> justfile already has mod line"
    else
        echo "" >> "$JUSTFILE"
        echo "$MOD_LINE" >> "$JUSTFILE"
        echo "  -> Added mod line to justfile"
    fi
else
    echo "$MOD_LINE" > "$JUSTFILE"
    echo "  -> Created justfile"
fi

echo ""
echo "Done! Next steps:"
echo "  just dev::setup    # one-time: install tools + build image"
echo "  just dev::up       # start sandbox"
echo "  just dev::claude   # run Claude Code (autonomous)"
