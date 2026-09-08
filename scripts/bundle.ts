import {bundleApp} from "./bundle-app";
const paint=process.argv.includes("--termpaint");
await bundleApp({entry:paint?"js/termpaint-entry.ts":"js/examples.ts",output:paint?"src/termpaint.js":"src/examples.js",demoAssets:!paint});
