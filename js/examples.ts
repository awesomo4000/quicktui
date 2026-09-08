// Static require calls become lazy module initializers in the single IIFE.
// Libraries are bundled once; only the selected demo installs its host hooks.
declare const __host:{example:string};
if(typeof __host==="undefined"){
  require("./smoke");
}else{
  require("./platform/bootstrap");
  switch(__host.example){
    case "counter": require("./counter");break;
    case "mouse": require("./mouse");break;
    case "reload": require("./reload");break;
    case "live": require("./live");break;
    case "lab": require("./lab");break;
    case "messages": require("./messages");break;
    case "editor":
    case "gallery": require("./gallery");break;
    default:throw new Error(`Unknown example: ${__host.example}`);
  }
}

export {};
