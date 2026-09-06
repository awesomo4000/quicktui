// This file adds another component to the existing page.
// Its effect is cleaned up when the component is replaced or removed.
api.register("clock", {
  title: "A clock added by a second script",
  render: function Clock() {
    const [now, setNow] = React.useState(new Date().toLocaleTimeString());
    React.useEffect(() => {
      const timer = setInterval(() => setNow(new Date().toLocaleTimeString()), 1000);
      return () => clearInterval(timer);
    }, []);
    return h("text", {fg: "#bfa9ec"}, "QuickJS time: " + now);
  }
});
