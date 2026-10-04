// Small assertion runner for the QuickJS input regression suite.
const cases: Array<{name:string,run:()=>unknown}> = [];
export function test(name:string,run:()=>unknown){cases.push({name,run})}
function equal(a:any,b:any):boolean {
 if(Object.is(a,b))return true;
 if(!a||!b||typeof a!=="object"||typeof b!=="object")return false;
 if(Object.getPrototypeOf(a)!==Object.getPrototypeOf(b))return false;
 const ak=Object.keys(a),bk=Object.keys(b);
 return ak.length===bk.length&&ak.every(k=>Object.prototype.hasOwnProperty.call(b,k)&&equal(a[k],b[k]));
}
export function expect(actual:any,negated=false):any {
 const check=(pass:boolean,message:string)=>{if(pass===negated)throw Error(`${negated?"not ":""}${message}; got ${String(actual)}`)};
 return {
  get not(){return expect(actual,!negated)},
  toBe(expected:any){check(Object.is(actual,expected),`expected ${String(expected)}`)},
  toEqual(expected:any){check(equal(actual,expected),"expected deep equality")},
  toHaveLength(expected:number){check(actual.length===expected,`expected length ${expected}`)},
  toBeCloseTo(expected:number,digits=2){check(Math.abs(actual-expected)<0.5*10**-digits,`expected approximately ${expected}`)},
  toBeGreaterThan(expected:number){check(actual>expected,`expected > ${expected}`)},
  toBeGreaterThanOrEqual(expected:number){check(actual>=expected,`expected >= ${expected}`)},
  toBeLessThan(expected:number){check(actual<expected,`expected < ${expected}`)},
 };
}
export async function runTests(){
 let count=0;
 for(const item of cases){try{await item.run();count++}catch(error){throw Error(`${item.name}: ${String(error)}`)}}
 console.log(`QuickJS input suite: ${count} tests passed`);
}
