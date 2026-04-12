#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$(dirname "$(realpath "$0")")"

echo ""
echo "claude-devcontainer -- install"
echo "=============================="
echo ""

# --- Check / install prerequisites ---

if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew is required. Install it from https://brew.sh"
    exit 1
fi

if ! command -v colima &>/dev/null; then
    echo "Installing colima..."
    brew install colima
fi

if ! command -v docker &>/dev/null; then
    echo "Installing Docker CLI..."
    brew install docker
fi

if ! command -v just &>/dev/null; then
    echo "Installing just..."
    brew install just
fi

if ! command -v node &>/dev/null; then
    echo "Installing Node.js..."
    brew install node
fi

if ! command -v devcontainer &>/dev/null; then
    echo "Installing devcontainer CLI..."
    npm install -g @devcontainers/cli
fi

# --- Start colima if needed ---

if ! colima status &>/dev/null 2>&1; then
    echo "Starting colima..."
    colima start
fi

# --- Build the base image ---

echo "Building claude-sandbox base image..."
BUILD_ARGS=()
if [ -n "${BASE_IMAGE:-}" ]; then
    echo "Using base image: $BASE_IMAGE"
    BUILD_ARGS+=(--build-arg "BASE_IMAGE=$BASE_IMAGE")
fi
docker build "${BUILD_ARGS[@]}" -t claude-sandbox "$INSTALL_DIR"

# --- Add shell alias ---

ALIAS_LINE="alias claude-devcontainer-init=\"$INSTALL_DIR/init.sh\""

SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ]; then
    SHELL_RC_REAL="$(realpath "$SHELL_RC")"
    if grep -qF "claude-devcontainer-init" "$SHELL_RC_REAL" 2>/dev/null; then
        echo "Alias already exists in $(basename "$SHELL_RC")"
    else
        echo "" >> "$SHELL_RC_REAL"
        echo "$ALIAS_LINE" >> "$SHELL_RC_REAL"
        echo "Added alias to $(basename "$SHELL_RC")"
    fi
else
    echo "Could not find .zshrc or .bashrc. Add this alias manually:"
    echo "  $ALIAS_LINE"
fi

echo ""
echo "Done! Next steps:"
echo ""
echo "  1. Reload your shell:  source $SHELL_RC"
echo "  2. Set up a project:   cd my-project && claude-devcontainer-init"
echo "  3. Start the sandbox:  just dev::up"
echo "  4. Launch Claude:      just dev::claude"
echo ""
echo "iTerm2: set the tmux profile window style to Maximized"
echo "  Preferences > Profiles > tmux > Window > Style: Maximized"
