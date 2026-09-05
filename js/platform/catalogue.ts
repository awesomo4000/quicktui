import { BoxRenderable, TextRenderable, ImageRenderable } from "./core";
import { SpanRenderable, BoldSpanRenderable, ItalicSpanRenderable, UnderlineSpanRenderable, LineBreakRenderable, LinkRenderable } from "../../vendor/opentui/packages/react/src/components/text";
const catalogue = {box:BoxRenderable,text:TextRenderable,image:ImageRenderable,span:SpanRenderable,b:BoldSpanRenderable,strong:BoldSpanRenderable,i:ItalicSpanRenderable,em:ItalicSpanRenderable,u:UnderlineSpanRenderable,br:LineBreakRenderable,a:LinkRenderable};
export const getComponentCatalogue=()=>catalogue;
