# Framework-neutral applications

`quicktui/core` runs a terminal application without React. `quicktui` remains the
compatible React entry point; `quicktui/react` is an explicit alias for it. Both
use the same input parser, terminal context, native renderer, and host lifecycle.
Use the QuickTUI bundler for all three entry points.

```js
import {createApplication} from "quicktui/core";

const app = createApplication({keyboard: {mode: "realtime"}});
const panel = app.box({border: true, padding: 1, height: "100%"});
const label = app.text({content: "Count: 0"});
app.root.add(panel);
panel.add(label);

let count = 0;
app.onKey(event => {
  if (event.ctrl && event.name === "c" && event.kind !== "release") {
    app.quit();
    return true;
  }
  if (event.name === "space") {
    if (event.kind === "press") label.content = `Count: ${++count}`;
    return true;
  }
});
```

The native caller runs the bundle with Zig `quicktui.runApp`. Calling
`createApplication` initializes its tree; there is no separate JS `run()` call.
The native host owns the event loop. Only one application may be created in a
QuickJS runtime. Native host reload replaces that runtime, not just its tree.

## Widgets and updates

- `app.root` is the root renderable.
- `app.box(options)` and `app.text(options)` construct unattached widgets.
- `app.create(Widget, options)` constructs another class from `quicktui/widgets`.
- `parent.add(child)` attaches it. `parent.insertBefore(child, anchor)` reorders
  or reparents it using the underlying renderable operations.
- Assign widget properties such as `label.content` to update them. Widget setters
  schedule rendering; the host presents the next frame without a manual redraw.
- `parent.remove(child)` detaches without destroying it. Use
  `child.destroyRecursively()` when finished with that subtree.
- `widget.focus()` uses the shared terminal focus and editor machinery.

The application destroys widgets made by its factories on shutdown, including
unattached widgets, and releases its registered subscriptions. Direct adapter
implementations must clean up their own unattached objects. Attached trees are
also destroyed by the shared runtime at shutdown.

This first API exposes OpenTUI renderable classes, not a DOM or a framework-neutral
property schema. Text widgets have their own content semantics. Adapters should
use documented widget setters and operations rather than assign arbitrary fields.

## Events and host services

`createApplication` accepts the shared options described in the
[application API](application-api.md): keyboard configuration, initial layout,
input/reset/capability callbacks, paste, native messages, disconnects, snapshot
export, and reload notices. React error-boundary handling remains specific to
the React adapter.

`app.onKey(handler)`, `app.onInputReset(handler)`, and `app.onResize(handler)`
return unsubscribe functions. Keyboard subscriptions receive normalized presses,
repeats, and releases when the terminal supplies them. App option `onKey` runs
before subscriptions; unconsumed input reaches the existing focused widgets.
Return true or prevent the event to consume it. Subscriptions are global, not
implicitly focused. There is no hook filter in this lower-level API; ordinary JS
conditions can filter `event.kind` or application state.

Terminal flags remain fixed for the native host lifetime. Observing an arrow
release does not establish letter-release support. See the
[keyboard compatibility record](keyboard-compatibility.md).

`quicktui/core` also exports `HeldKeys`, keyboard types, `quit`, `sendMessage`,
`takeBuffer`, and the existing reload helpers. These are the same implementations
used by the React entry point. This adds no filesystem, socket, or process access.

## Writing a framework adapter

`mountApplication(adapter, options)` is the lower-level entry point used by the
React adapter and the vanilla factory. The adapter provides:

```ts
interface ApplicationAdapter {
  mount(root: RootRenderable, context: any): void;
  unmount(): void;
  batch?(work: () => void): void;
  inspect?(): Record<string, unknown>;
}
```

`mount` receives the shared widget root and render context. `unmount` disposes
framework state before the shared tree and native wrappers are cleaned up.
`batch` wraps an incoming input batch; the React adapter uses its synchronous
reconciler batching. Without it, work executes directly. `inspect` is optional
headless diagnostic metadata.

The context currently follows the existing OpenTUI render context and is not yet
a narrowed, stable adapter contract. This is an initial extraction. Elm, Solid,
and Svelte adapters are not included. Each needs its own tree/property/event
translation and lifecycle integration; they do not need new terminal protocols
or native message implementations. Browser components and DOM APIs are not
provided by this layer.

## Connecting an Elm application

Keep the QuickTUI calls in one JavaScript adapter. Elm can continue to own its
model, update function, and a serializable description of the desired widget
tree. The adapter translates that description into widgets and sends widget
events back through Elm ports.

Start with `createApplication` and the vanilla example. Preserve widget instances
by stable node IDs when applying new trees, update their properties, and destroy
removed nodes. Recreating an input on every update would lose its local caret,
selection, and focus unless the adapter explicitly restores them.

Send plain event records through ports, such as key identity, event kind, text,
and modifier flags. Decide synchronous event consumption in JavaScript before
returning from the key handler. A later Elm message cannot retroactively stop
the focused widget from handling that key.

Use `mountApplication` when the adapter needs its own mount/unmount lifecycle or
batching. Unsubscribe Elm port listeners during unmount and dispose any adapter
resources. Its optional `batch` callback must execute the supplied work
synchronously.

The core and vanilla consumer are tested; an Elm adapter has not yet been
validated here. Keeping the translation in one module also limits changes if
the render-context contract is refined during consumer testing. Existing
`quicktui` React imports continue to work during migration.

## Example and verification

See [the vanilla consumer](../examples/vanilla/README.md). `zig build test-vanilla`
builds it outside this checkout and checks rendering, input, node updates,
subscription cleanup, paste/resize, and PTY shutdown. `zig build test-bundler`
checks that its source map includes no React, reconciler, or scheduler modules.
License notices may still mention those vendored dependencies; that does not
mean their runtime code is included.
