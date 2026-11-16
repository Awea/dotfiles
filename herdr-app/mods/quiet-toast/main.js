// The toast mod of the main-quiet layout: no notification. Each toast closes at once,
// an error too, and draws nothing.
import { View, div } from "gpui-kit";
import { props, closeOverlay } from "herdr";

export default class QuietToast extends View {
  init() {
    // herdr-app check gives no overlay id.
    const id = props()?.overlay;
    if (id) closeOverlay(id);
  }

  render() {
    return div();
  }
}
