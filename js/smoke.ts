import React from "../vendor/js/node_modules/react";
import Reconciler from "../vendor/js/node_modules/react-reconciler";

declare function nativeProbe(): number;
declare function print(...values: unknown[]): void;

const element = React.createElement("text", null, "QuickTUI");
if (!React.isValidElement(element) || typeof Reconciler !== "function") {
  throw new Error("React dependencies failed to initialize");
}
if (nativeProbe() !== 32) throw new Error("OpenTUI native buffer probe failed");
Promise.resolve().then(() => {
  print(`QuickTUI: React ${React.version}, QuickJS, and static OpenTUI are ready.`);
  print("Shared React libraries and native buffer bindings verified.");
});
