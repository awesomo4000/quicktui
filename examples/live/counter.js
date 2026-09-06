// Loaded from disk by the running app. No bundling or restart needed.
// Edit the title, colors, or markup, then press R (or enable W watch).
api.register("counter", {
  title: "A counter loaded from JavaScript",
  render: function Counter() {
    const [count, setCount] = React.useState(0);
    return h("box", {flexDirection: "row", gap: 2},
      h("text", {fg: "#edce86"}, "Extension count: " + count),
      h("box", {paddingX: 1, backgroundColor: "#294650", onMouseDown: () => setCount(n => n + 1)},
        h("text", {fg: "#85ddca"}, "Click +1")));
  }
});
