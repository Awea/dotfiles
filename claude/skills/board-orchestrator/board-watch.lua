-- The board watcher of a Renux session. Rex does not tell an orchestrator that a worker is
-- blocked, exited or closed, so this script does: it calls dispatch.sh notice for each event.
-- board.sh starts it with:
--   rex do -s SESSION board-watch.lua dispatch=PATH session=SESSION outbox=PATH
-- A handler gets fn(ctx, ev). ctx holds session_id and block_id. ev holds the fields of the
-- event: record for a status change, exit_code for an exit, block_id for a closed block,
-- session_id for a destroyed session. Block events and block_closed reach a script only from
-- its own session. session_destroyed fires for every session, so the script ends only for
-- its own.
--
-- The script also delivers the queue of the messages to the orchestrators of its session
-- (outbox). Rex does not tell when a user types, so a message waits in the queue, and
-- dispatch.sh deliver sends it when the input box of the orchestrator stays empty.
--
-- Every 10 minutes, the script runs rex-job --sweep: it closes the ended jobs that no live
-- block uses, also when a worker went away with no dispatch.sh close (the user closed its
-- tab). A sweep costs about 0.6 s of CPU, so not more often. It also runs dispatch.sh
-- sweep: it stops the dev servers of a worktree with no worker, and tells the orchestrator
-- when the swap or the RAM is low.
local dispatch = rex.args.dispatch
local own = rex.args.session
local outbox = rex.args.outbox

local function notice(block, state, detail)
  rex.exec({ dispatch, "notice", block, state, tostring(detail or "") })
end

rex.on("terminal.program_status_changed", function(ctx, ev)
  local record = ev.record or {}
  if record.state == "blocked" or record.state == "working" then
    notice(ctx.block_id, record.state, record.msg)
  end
end)

rex.on("terminal.child_exited", function(ctx, ev)
  notice(ctx.block_id, "exited", ev.exit_code)
end)

-- The user closed the tab of a running block: Rex sends block_closed and no exit.
rex.on("block_closed", function(ctx, ev)
  notice(ev.block_id or ctx.block_id, "closed")
end)

rex.on("session_destroyed", function(ctx, ev)
  if ev.session_id == own then
    os.exit(0)
  end
end)

-- Each second: test -s is cheap, and dispatch.sh runs only while the queue has lines.
if outbox then
  rex.every(1, function()
    local has = rex.exec({ "test", "-s", outbox })
    if not (has and has.ok) then
      return
    end
    -- deliver writes its errors to the watcher log itself.
    rex.exec({ dispatch, "deliver", own }, { timeout = 30 })
  end)
end

-- In the background: the sweep can wait for the lock of rex-resource. dispatch.sh sweep
-- stops the dev servers of the worktrees with no worker and tells a low swap or RAM.
rex.every(600, function()
  rex.exec({ "sh", "-c", 'f="$HOME/.bin/rex-job"; [ -x "$f" ] || exit 0; ("$f" --sweep >/dev/null 2>&1 </dev/null &)' })
  rex.exec({ "sh", "-c", '("$0" sweep "$1" >/dev/null 2>&1 </dev/null &)', dispatch, own })
end)
