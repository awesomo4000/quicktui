import { Lexer } from "../../vendor/js/node_modules/marked";

type Capture=[number,number,string,{conceal?:string,isInjection?:boolean}?];
// Preserve OpenTUI's Code/Markdown rendering pipeline without workers or WASM.
// Marked supplies Markdown tokens; programming-language code stays plain text.
export function markdownHighlights(content:string):Capture[]{
  const captures:Capture[]=[];
  const add=(start:number,end:number,group:string)=>{if(end>start)captures.push([start,end,group])};
  const hide=(start:number,end:number)=>{if(end>start)captures.push([start,end,"conceal",{conceal:"",isInjection:true}])};
  function inline(tokens:any[],base:number){
    let offset=base;
    for(const token of tokens){
      const raw=token.raw??"";
      const start=content.indexOf(raw,offset);if(start<0)continue;
      const end=start+raw.length;offset=end;
      const groups:Record<string,string>={strong:"markup.strong",em:"markup.italic",del:"markup.strikethrough",codespan:"markup.raw",link:"markup.link"};
      if(groups[token.type]){
        // Marked keeps source markup in token.text for nested inline tokens.
        const text=token.text??"";const relative=raw.indexOf(text);
        if(relative>=0){
          const inner=start+relative;add(inner,inner+text.length,groups[token.type]);
          hide(start,inner);hide(inner+text.length,end);
          if(token.tokens)inline(token.tokens,inner);
        }
      }else if(token.type==="escape")hide(start,start+1);
      else if(token.tokens)inline(token.tokens,start);
    }
  }
  let offset=0;
  for(const token of Lexer.lex(content) as any[]){
    const start=content.indexOf(token.raw,offset);if(start<0)continue;
    const end=start+token.raw.length;offset=end;
    if(token.type==="heading"){
      const relative=token.raw.indexOf(token.text);
      if(relative>=0){const inner=start+relative;hide(start,inner);add(inner,inner+token.text.length,"markup.heading");hide(inner+token.text.length,end-(token.raw.endsWith("\n")?1:0));if(token.tokens)inline(token.tokens,inner)}
    }else if(token.tokens)inline(token.tokens,start);
  }
  return captures;
}
export class TreeSitterClient {
  async highlightOnce(content:string,filetype:string){return {highlights:filetype==="markdown"?markdownHighlights(content):[]}}
}
const client=new TreeSitterClient();
export const getTreeSitterClient=()=>client;
