import * as core from "./core";
import { SpanRenderable, BoldSpanRenderable, ItalicSpanRenderable, UnderlineSpanRenderable, LineBreakRenderable, LinkRenderable } from "../../vendor/opentui/packages/react/src/components/text";
const catalogue={"box":core.BoxRenderable,"text":core.TextRenderable,"image":core.ImageRenderable,"input":core.InputRenderable,"textarea":core.TextareaRenderable,"select":core.SelectRenderable,"tab-select":core.TabSelectRenderable,"scrollbox":core.ScrollBoxRenderable,"ascii-font":core.ASCIIFontRenderable,"code":core.CodeRenderable,"diff":core.DiffRenderable,"markdown":core.MarkdownRenderable,"line-number":core.LineNumberRenderable,"slider":core.SliderRenderable,"scrollbar":core.ScrollBarRenderable,"table":core.TextTableRenderable,span:SpanRenderable,b:BoldSpanRenderable,strong:BoldSpanRenderable,i:ItalicSpanRenderable,em:ItalicSpanRenderable,u:UnderlineSpanRenderable,br:LineBreakRenderable,a:LinkRenderable};
export const getComponentCatalogue=()=>catalogue;

export function extend(objects:Record<string,any>){Object.assign(catalogue,objects)}
