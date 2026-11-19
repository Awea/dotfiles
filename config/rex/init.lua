-- The Rex config for Renux: the keys, with ctrl+b as a prefix as in tmux, the popups and
-- the actions. A session holds the tabs (session windows), a tab holds the panes.
--
-- Renux matches the typed character and names it as a US keyboard does: on AZERTY, the "
-- key is shift+' and % is shift+5. Renux does not read physical names such as [Digit1].
--
-- Not here: alt-1..9 (Renux has no action to go to a session by number), agent
-- next/previous, help, the go-to picker, layout switch and paste image.

local function bind_all(keys, action, args)
  for _, key in ipairs(keys) do rex.bind(key, action, args) end
end

-- Panes
for _, d in ipairs({ "left", "down", "up", "right" }) do
  local vim = ({ left = "h", down = "j", up = "k", right = "l" })[d]
  rex.bind("alt+" .. vim, "pane.focus", { direction = d })
  rex.bind("alt+shift+" .. vim, "pane.move", { direction = d })
end
rex.bind("alt+left", "pane.focus", { direction = "left" })
rex.bind("alt+right", "pane.focus", { direction = "right" })
rex.bind("ctrl+shift+o", "pane.split", { direction = "right" })
rex.bind("ctrl+shift+e", "pane.split", { direction = "down" })
rex.bind("ctrl+shift+x", "pane.close")
rex.bind("ctrl+shift+z", "pane.zoom")

-- Tabs
for i = 1, 9 do
  rex.bind("ctrl+" .. i, "client.tab.goto", { index = i })
end
bind_all({ "ctrl+pagedown", "ctrl+tab" }, "client.tab.next")
bind_all({ "ctrl+pageup", "ctrl+shift+tab" }, "client.tab.previous")
rex.bind("ctrl+shift+t", "client.tab.new")
rex.bind("ctrl+shift+w", "client.tab.close")
rex.bind("f2", "client.tab.rename")

-- Sessions
rex.bind("ctrl+shift+pagedown", "session.next")
rex.bind("ctrl+shift+pageup", "session.previous")
rex.bind("ctrl+shift+n", "session.new")
rex.bind("shift+f2", "session.rename")

-- App
rex.bind("ctrl+shift+b", "client.sidebar.toggle")
rex.bind("ctrl+shift+p", "client.palette.toggle")
rex.bind("ctrl+,", "client.settings")
bind_all({ "ctrl+=", "ctrl+shift+=" }, "client.font.increase")
rex.bind("ctrl+-", "client.font.decrease")
rex.bind("ctrl+0", "client.font.reset")

-- Terminal
rex.bind("ctrl+backspace", "pane.send_key", { key = "ctrl+w" })
rex.bind("ctrl+left", "pane.send_key", { key = "alt+b" })
rex.bind("ctrl+right", "pane.send_key", { key = "alt+f" })
bind_all({ "ctrl+shift+c", "ctrl+insert" }, "pane.copy")
bind_all({ "ctrl+shift+v", "shift+insert" }, "pane.paste")
rex.bind("ctrl+shift+f", "client.find.open")

-- ctrl+b: the prefix keys that need no popup
local prefix = {
  c = { "client.tab.new" },
  v = { "pane.split", { direction = "right" } },
  ["shift+5"] = { "pane.split", { direction = "right" } }, -- %
  ["shift+'"] = { "pane.split", { direction = "down" } }, -- "
  ["-"] = { "pane.split", { direction = "down" } },
  x = { "pane.close" },
  z = { "pane.zoom" },
  h = { "pane.focus", { direction = "left" } },
  j = { "pane.focus", { direction = "down" } },
  k = { "pane.focus", { direction = "up" } },
  l = { "pane.focus", { direction = "right" } },
  tab = { "pane.focus", { direction = "right" } },
  ["shift+tab"] = { "pane.focus", { direction = "left" } },
  n = { "client.tab.next" },
  p = { "client.tab.previous" },
  b = { "client.sidebar.toggle" },
  s = { "client.settings" },
  ["shift+t"] = { "client.tab.rename" },
  ["shift+w"] = { "session.rename" },
  ["shift+d"] = { "session.close" },
}
for key, a in pairs(prefix) do rex.bind("ctrl+b>" .. key, a[1], a[2]) end
-- After ctrl+b, a digit is shift+digit on AZERTY. Renux names % shift+5 too, so % (split
-- right) takes shift+5 and ctrl+b has no tab 5.
for i = 1, 9 do
  if i ~= 5 then rex.bind("ctrl+b>shift+" .. i, "client.tab.goto", { index = i }) end
end
-- Popups: a script of bin/ in a floating pane at the top of the window. The script gets
-- the folder of the focused pane, the session, the focused block and the client. height
-- is a fraction of the window height (default 0.3). The pane closes when the script ends.
local bin = os.getenv("HOME") .. "/.config/rex/bin/"

-- pane(ctx): the focused block of ctx as session.describe_block gives it, and its folder.
local function pane(ctx)
  local session = ctx.session_id
  local block, err = rex.call("session.describe_block", { session_id = session, block_id = ctx.block_id })
  if err ~= nil then error(err, 0) end
  local p = rex.call("block.method", { session_id = session, block_id = ctx.block_id, method = "process" }) or {}
  return block.block, (p.foreground or p.child or {}).cwd or os.getenv("HOME")
end

local function popup(ctx, script, height)
  local session = ctx.session_id
  local block, cwd = pane(ctx)
  local _, lerr = rex.session.new_layer{
    session_id = session,
    window_id = block.window_id,
    bounds = { x = 0.2, y = 0.05, w = 0.6, h = height or 0.3 },
    focus = true,
    layout = rex.layout.block{
      flavor = "com.superlogical.terminal.shell",
      options = { command = { bin .. script, cwd, session, ctx.block_id, ctx.client_id or "" }, cwd = cwd },
    },
  }
  if lerr ~= nil then error(lerr, 0) end
end

rex.action{
  name = "new_agent_tab",
  title = "New Claude Tab",
  run = function(ctx) popup(ctx, "new-agent-tab.sh") end,
}
rex.bind("ctrl+b>a", "new_agent_tab")

rex.action{
  name = "handoff",
  title = "Handoff to a New Claude Tab",
  run = function(ctx) popup(ctx, "handoff.sh") end,
}
rex.bind("ctrl+b>shift+a", "handoff")

rex.action{
  name = "new_space",
  title = "New Space",
  run = function(ctx) popup(ctx, "new-space.sh", 0.5) end,
}
rex.bind("ctrl+b>shift+n", "new_space")

-- ctrl+b shift+b and shift+x: open and stop a board orchestrator (bin/board-open.sh and
-- bin/board-stop.sh). Both call board.sh.
rex.action{
  name = "board_open",
  title = "Open a Board Orchestrator",
  run = function(ctx) popup(ctx, "board-open.sh") end,
}
rex.bind("ctrl+b>shift+b", "board_open")

rex.action{
  name = "board_stop",
  title = "Stop a Board Orchestrator",
  run = function(ctx) popup(ctx, "board-stop.sh") end,
}
rex.bind("ctrl+b>shift+x", "board_stop")

-- ctrl+b shift+l: the branch view of a picked repo (bin/branches-pick.sh): serie, a graph
-- of the branches and their commits. It opens a pane on the right of the focused pane,
-- with serie on the repo of the focused pane. q in serie shows a list of repos in that
-- pane, and Esc in the list closes the pane. Not ctrl+b g: it stays free for the go-to
-- picker.
rex.action{
  name = "branches",
  title = "Git Branch View (serie)",
  run = function(ctx)
    local session = ctx.session_id
    local block, cwd = pane(ctx)
    local _, err = rex.call("session.new_split", {
      session_id = session,
      anchor_id = block.block_id,
      direction = "horizontal",
      side = "after",
      focus = true,
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        options = {
          command = { bin .. "branches-pick.sh", cwd, session, ctx.block_id, ctx.client_id or "" },
          cwd = cwd,
        },
      },
    })
    if err ~= nil then error(err, 0) end
  end,
}
rex.bind("ctrl+b>shift+l", "branches")

-- ctrl+b d: herdr-reviewr in the branch scope on the git root to review (bin/reviewr-pick),
-- zoomed. That is the worktree and base that an agent set with bin/reviewr-target, else the
-- git root of the focused folder and the commit where its branch left the default branch
-- (the upstream on the default branch). It shows the reviewr of that root in the window,
-- else opens one in a split on the right (bin/reviewr.sh). A reviewr pane has the label
-- "reviewr ROOT", or "reviewr ROOT BASE" with a base.
rex.action{
  name = "reviewr",
  title = "Review the Branch",
  run = function(ctx)
    local session = ctx.session_id
    local block, cwd = pane(ctx)
    local root, base = cwd, nil
    local r = rex.exec({ bin .. "reviewr-pick", block.block_id, cwd }, { timeout = 2 })
    if r ~= nil and r.ok then
      local line1, line2 = r.stdout:match("^([^\n]*)\n([^\n]*)")
      if line1 ~= nil and line1 ~= "" then root = line1 end
      if line2 ~= nil and line2 ~= "" then base = line2 end
    else
      local g = rex.exec({ "git", "-C", cwd, "rev-parse", "--show-toplevel" }, { timeout = 2 })
      if g ~= nil and g.ok and g.stdout:match("%S") then root = g.stdout:gsub("%s+$", "") end
    end
    local label = "reviewr " .. root
    if base ~= nil then label = label .. " " .. base end
    local target
    if (block.label or ""):match("^reviewr ") then target = block.block_id end
    if target == nil then
      local list = rex.call("session.list_blocks", { session_id = session }) or { blocks = {} }
      for _, b in ipairs(list.blocks) do
        if b.window_id == block.window_id and b.label == label then target = b.block_id end
      end
    end
    if target == nil then
      local reviewr_cmd = { bin .. "reviewr.sh", root }
      if base ~= nil then table.insert(reviewr_cmd, base) end
      local split, err = rex.call("session.new_split", {
        session_id = session,
        anchor_id = block.block_id,
        direction = "horizontal",
        side = "after",
        focus = true,
        layout = rex.layout.block{
          flavor = "com.superlogical.terminal.shell",
          options = { command = reviewr_cmd, cwd = root },
        },
      })
      if err ~= nil then error(err, 0) end
      target = split.block_ids[1]
      rex.call("session.set_block_label", { session_id = session, block_id = target, label = label })
    end
    local _, zerr = rex.call("session.zoom_block", { session_id = session, block_id = target, zoom = true })
    if zerr ~= nil then error(zerr, 0) end
  end,
}
rex.bind("ctrl+b>d", "reviewr")

-- Resume claude in the panes that lost it at a server restart (bin/claude-resume.sh). Each
-- config load starts the loop. A second loop exits at once.
rex.exec.start({ bin .. "claude-resume.sh", "loop" }, { detach = true })

-- ctrl+b i: the activity view of the sidebar, a list of the agents. It shows which program works, is blocked or needs you. ctrl+b I groups it by
-- session. Renux runs these actions only from a key: rex do -C does nothing.
rex.bind("ctrl+b>i", "client.sidebar.activity.toggle")
rex.bind("ctrl+b>shift+i", "client.sidebar.activity.by_session")

-- A second ctrl+b sends ctrl+b to the program, as tmux send-prefix does: in a tmux of the
-- pane, ctrl+b ctrl+b c opens a tmux window. Use pane.send_key, not a Lua function: Renux
-- drops a key bound to a Lua function (client.key.forward), so the program gets nothing.
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })
