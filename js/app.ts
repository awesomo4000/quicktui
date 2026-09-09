/** React application entry point, retained for compatibility. */
export {mountApp,type AppOptions} from "./platform/demo";
export * from "./services";
export {HeldKeys,AppKeyEvent,type KeyboardOptions,type KeyboardCapabilities,type InputReset,type InputResetReason} from "./keyboard";

export {useKeyboardEvents,type KeyboardEventOptions} from "./keyboard-hooks";
