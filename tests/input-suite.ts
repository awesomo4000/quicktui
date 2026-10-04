import {createApplication} from "quicktui/core";
import {testApp} from "quicktui/testing";
import {runTests} from "./assert";
import "./paste.test";
import "./keyboard.test";
const app=createApplication();
app.root.add(app.text({content:"Input regression tests"}));
testApp(async()=>{await runTests()});
