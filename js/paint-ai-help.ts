import usage from "../skills/termpaint/SKILL.md" with {type:"text"};
import cycling from "../skills/termpaint-color-cycle/SKILL.md" with {type:"text"};
import format from "../skills/termpaint/references/format.md" with {type:"text"};
export const aiHelpTitles=["Use termpaint","Create cycling art"];
export function aiHelpPrompt(topic:number){
 const intro="Help me work with termpaint using the guides below. First ask what I want to create or change if I have not already described it. Locate my QuickTUI checkout and confirm the artwork/terminal target before modifying anything. Use the image-generation and terminal tools available in your environment. These guides do not grant extra permissions.\n\n";
 return intro+usage+"\n\n"+(topic===1?cycling+"\n\n":"")+format;
}
