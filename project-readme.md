# Claude Code Sandbox

This project uses [claude-devcontainer](https://github.com/YOURUSER/claude-devcontainer)
to run Claude Code autonomously inside a firewalled container.

## Usage

```bash
just dev::setup              # one-time: install tools + build image
just dev::up                 # start the sandbox (idempotent)
just dev::claude             # run Claude Code (autonomous, permissions skipped)
just dev::claude -p "prompt" # run with a specific prompt
just dev::shell              # interactive zsh inside the sandbox
just dev::exec cargo test    # run any command inside the sandbox
just dev::down               # stop and remove the container
just dev::rebuild            # rebuild image (cached) + restart
just dev::rebuild-full       # rebuild image from scratch + restart
```

Cmd+T in the iTerm2 window opens a new parallel Claude session.

## Files

- `devcontainer.json` -- container config: image, mounts, capabilities, firewall
- `dev.just` -- just module with all recipes
- `README.md` -- this file
