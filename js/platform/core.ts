export { Renderable, RootRenderable, isRenderable } from "../../vendor/opentui/packages/core/src/Renderable";
export { BoxRenderable } from "../../vendor/opentui/packages/core/src/renderables/Box";
export { TextRenderable } from "../../vendor/opentui/packages/core/src/renderables/Text";
export { TextNodeRenderable } from "../../vendor/opentui/packages/core/src/renderables/TextNode";
export { TextAttributes } from "../../vendor/opentui/packages/core/src/types";
export { ImageRenderable } from "../../vendor/opentui/packages/core/src/renderables/Image";
// These types only occur in guarded branches of the upstream host config and
// property setter. They are absent from the component catalogue, and fail if used.
class UnsupportedRenderable { constructor(){throw new Error("Unsupported component in counter profile")} }
export { UnsupportedRenderable as InputRenderable, UnsupportedRenderable as SelectRenderable, UnsupportedRenderable as TabSelectRenderable, UnsupportedRenderable as TextareaRenderable };
export const InputRenderableEvents = {}, SelectRenderableEvents = {}, TabSelectRenderableEvents = {};
