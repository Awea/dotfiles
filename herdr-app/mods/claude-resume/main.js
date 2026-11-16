// Resume Claude in the terminals that lost it at a restart. The main-quiet layout holds
// this mod in a block of 0 px, so it starts with the window and draws nothing.
// claude-resume.sh tick does the work after the window shows, and again every 30 seconds:
// it resumes Claude in each terminal that lost it, and records the Claude session of
// each other terminal. It is safe to run again.
import { View, div } from "gpui-kit";
import { exec, home, checking } from "herdr";

const SCRIPT = () => `${home()}/.config/herdr-app/bin/claude-resume.sh`;
const TICK_MS = 30000;

// run(command, ms): run claude-resume.sh with command, and log a failure.
async function run(command, ms) {
  try {
    const r = await exec("bash", [SCRIPT(), command], { timeout: ms });
    if (r.code !== 0) console.log(`claude-resume ${command}: ${r.stderr}`);
    else if (r.stdout) console.log(r.stdout);
  } catch (e) {
    console.log(`claude-resume ${command}: ${e?.message ?? e}`);
  }
}

export default class ClaudeResume extends View {
  init(_props, cx) {
    // herdr-app check runs init for real: a check must not type in a live terminal.
    if (checking()) return;
    cx.spawn(async (cx) => {
      for (;;) {
        // A send waits while the person types in that terminal: give a tick 5 minutes.
        await run("tick", 300000);
        await cx.sleep(TICK_MS);
      }
    });
  }

  render() {
    return div();
  }
}
