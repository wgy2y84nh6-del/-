// Optional smoke test against a locally running Firefox --remote-debugging-port 9223.
// Uses standard WebDriver BiDi directly; no patched Firefox or driver required.
const fs=require('fs'),assert=require('node:assert/strict'),path=require('path');
const out=process.env.HOME_TEST_OUTPUT||'/tmp/home-firefox-results';fs.mkdirSync(out,{recursive:true});
const report={checks:[],errors:[]};let sequence=0;const pending=new Map();
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const ws=new WebSocket('ws://127.0.0.1:9223/session');
ws.onmessage=e=>{const r=JSON.parse(e.data);if(r.id){const p=pending.get(r.id);if(p){pending.delete(r.id);r.type==='error'?p.reject(Error(r.error+': '+r.message)):p.resolve(r.result)}}else if(r.method==='log.entryAdded' && r.params.level==='error'){report.errors.push(r.params.text)}};
function command(method,params={}){return new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}))})}
function check(value,title){assert.ok(value,title);report.checks.push(title);console.log('PASS:',title)}
(async()=>{
 await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject});
 const session=await command('session.new',{capabilities:{}});report.browser=session.capabilities.browserVersion;
 await command('session.subscribe',{events:['log.entryAdded']});
 const {context}=await command('browsingContext.create',{type:'tab'});
 const evaluate=async expression=>(await command('script.evaluate',{expression,target:{context},awaitPromise:true})).result;
 const state=async()=>{const r=await evaluate('JSON.stringify(window.__homeState||null)');return JSON.parse(r.value)};
 const eventually=async fn=>{const end=Date.now()+60000;while(Date.now()<end){if(await fn())return;await wait(150)}throw Error('Firefox readiness timeout')};
 const click=async(x,y)=>{await command('input.performActions',{context,actions:[{type:'pointer',id:'mouse',parameters:{pointerType:'mouse'},actions:[{type:'pointerMove',x,y,origin:'viewport'},{type:'pointerDown',button:0},{type:'pointerUp',button:0}]}]});await wait(250)};
 try{
  await command('browsingContext.setViewport',{context,viewport:{width:1600,height:900},devicePixelRatio:1});
  await command('browsingContext.navigate',{context,url:process.env.HOME_TEST_URL||'http://127.0.0.1:8765/',wait:'complete'});
  await eventually(async()=> (await state())?.mode==='menu');
  report.browser=await evaluate('navigator.userAgent');
  check(true,'Firefox loads WASM and renders main menu');
  await click(800,290);await eventually(async()=> (await state())?.mode==='game');
  check((await state()).pets.length===1,'Firefox starts a new game');
  const shot=await command('browsingContext.captureScreenshot',{context});fs.writeFileSync(path.join(out,'firefox-heart.png'),Buffer.from(shot.data,'base64'));
  await click(710,835);let s=await state();const food=s.food;
  check(s.view==='brain','Firefox navigation opens brain');
  await click(1115,340);s=await state();
  check(s.food===food+1 && !s.available_food.brain,'Firefox food collection adds one and clears slot');
  await click(1115,340);check((await state()).food===food+1,'Firefox rejects duplicate collection');
  const at=(await state()).elapsed;
  for(let i=0;i<4;i++) for(const x of [160,430,710,980]) await click(x,835);
  check((await state()).elapsed>at+2,'Firefox repeated navigation does not freeze simulation');
  await click(430,835);
  await command('input.performActions',{context,actions:[{type:'pointer',id:'mouse',parameters:{pointerType:'mouse'},actions:[{type:'pointerMove',x:1410,y:336,origin:'viewport'},{type:'pointerDown',button:0}]}]});
  await wait(450);check((await state()).petting && (await state()).hearts===3,'Firefox hold displays three hearts');
  await command('input.performActions',{context,actions:[{type:'pointer',id:'mouse',parameters:{pointerType:'mouse'},actions:[{type:'pointerUp',button:0}]}]});
  await wait(200);check(!(await state()).petting,'Firefox release removes hearts');
  await click(1410,450);const energy=(await state()).pets[0].energy;await wait(1000);
  check((await state()).pets[0].sleeping && (await state()).pets[0].energy>energy,'Firefox sleep restores energy');
  await click(1410,450);
  await click(860,47);const paused=(await state()).elapsed;await wait(800);
  check((await state()).paused && (await state()).elapsed===paused,'Firefox pause freezes simulation');
  await click(860,47);await wait(2500);const before=await state();
  await command('browsingContext.reload',{context,wait:'complete'});
  await eventually(async()=> (await state())?.mode==='menu');await click(800,290);await eventually(async()=> (await state())?.mode==='game');s=await state();
  check(s.food===before.food && s.elapsed>=before.elapsed-2.1,'Firefox restores browser save after reload');
  check(report.errors.length===0,'Firefox has no game JavaScript or Godot errors');
 }catch(error){report.failure=String(error);report.lastState=await state().catch(()=>null);report.page=await evaluate('document.body.innerText').catch(()=>null);throw error}
 finally{fs.writeFileSync(path.join(out,'firefox-report.json'),JSON.stringify(report,null,2));await command('browsingContext.close',{context}).catch(()=>{});ws.close()}
})().catch(e=>{console.error(e);process.exitCode=1;ws.close()});
