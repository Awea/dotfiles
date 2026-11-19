-- The board watcher of a Renux session. Rex does not tell an orchestrator that a worker is
-- blocked or exited, so this script does: it calls dispatch.sh notice for each event.
-- board.sh starts it with: rex do -s SESSION board-watch.lua dispatch=PATH session=SESSION
-- A handler gets fn(ctx, ev). ctx holds session_id and block_id. ev holds the fields of the
-- event: record for a status change, exit_code for an exit, session_id for a destroyed
-- session. Block events reach a script only from its own session. session_destroyed fires
-- for every session, so the script ends only for its own.
local dispatch = rex.args.dispatch
local own = rex.args.session

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

rex.on("session_destroyed", function(ctx, ev)
  if ev.session_id == own then
    os.exit(0)
  end
end)
