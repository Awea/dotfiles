A blocked record has `state` "blocked", `kind` "permission", and `msg` "approve Bash: touch /tmp/probe-61" (an untrusted cwd gives msg "trust this folder"); Claude working gives "working", ready gives "idle" (no kind, no msg).
`child_exited` fired once for the terminal child (payload `exit_code`); it carries `block_id`, and a Claude block started with `-- claude` has no shell, so the session is destroyed right after `/exit` and `block.method process` then fails (process-shell.json comes from a bare shell block: child and foreground are `zsh`).
Block events (`program_status_changed`, `child_exited`, source "session") came only from the `-s` session; `session_destroyed` has source "server" and also fires for other sessions (a watcher heard a throwaway session die).
`os.exit(0)` in a handler ends `rex do` at once (checked twice, the process was gone after `session_destroyed`).
In a Rex pane `env | grep -E '^(HC_|REX_)'` gives REX_SESSION, REX_BLOCK and REX_BIN_DIR, and no HC_ variable.
Note: `program_status_changed` carries the `record` in `ctx.record`; `ev` has only block_id and session_id. The watcher started after the first blocked state, so that change has no event line (read it with block.method).
`process-exited.json` is the real `block.method process` answer of a `--keep-open` block whose command ended: `last_exit` is set and there is no `child`.
