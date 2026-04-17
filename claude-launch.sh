#!/usr/bin/env bash
# Launcher used by tmux default-command AND by the plain `devcontainer exec`
# path. If CLAUDE_TAB_RGB="R;G;B" is set in the tmux session env, emit an
# iTerm2 "tab color" escape (OSC 1337), wrapped in tmux's DCS passthrough so
# the sequence reaches iTerm2 untouched. Any args are forwarded to claude.
#
# The escape is emitted twice — once immediately and once ~0.3s later from a
# backgrounded subshell — because iTerm2 sometimes hasn't finished associating
# the new tmux window with a native tab by the time the first one fires, and
# claude's own terminal init can clobber it. Two shots makes it stick.

# Strip host-only env vars that leak into the container via `devcontainer exec`.
# cmux injects NODE_OPTIONS=--require=/var/folders/.../restore-node-options.cjs
# for its host-side Claude Code integration; that path doesn't exist in the
# Linux container and crashes node on startup. Same idea for anything pointing
# at /Applications (macOS app bundles) or /Users (host home).
case "${NODE_OPTIONS:-}" in
    *"/var/folders/"*|*"/Applications/"*|*"/Users/"*) unset NODE_OPTIONS ;;
esac

if [ -n "${CLAUDE_TAB_RGB:-}" ]; then
    IFS=';' read -r R G B <<< "$CLAUDE_TAB_RGB"
    set_tab_color() {
        printf '\033Ptmux;\033\033]1337;SetColors=tab=%02x%02x%02x\007\033\\' "$R" "$G" "$B" || true
    }
    set_tab_color
    (sleep 0.3; set_tab_color) &
fi

# Clear visible screen so claude's UI starts on a clean slate, especially in the
# plain (non-iTerm2) path where `devcontainer exec`/`colima start` chatter would
# otherwise sit above the prompt. Scrollback is preserved (\033[H\033[2J only —
# no \033[3J), so the launch log stays reachable by scrolling up.
printf '\033[H\033[2J'

exec claude --dangerously-skip-permissions "$@"
