// Controlled saved-game fixture; actual GUI inputs and real 20/50/40-second timers.
// No production debug commands, time scaling or live-state overrides are used.
const {chromium}=require('playwright');
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const out=process.env.HOME_TEST_OUTPUT||'/tmp/home-rebirth-browser';fs.mkdirSync(out,{recursive:true});
const report={checks:[],errors:[],events:[]};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function check(ok,title){assert.ok(ok,title);report.checks.push(title);console.log('PASS:',title)}
function pet(id){return {id,name:['Пух','Лилу','Ростик'][id-1],organ:['heart','brain','gut'][id-1],hunger:85,energy:85,joy:85,health:100,sleeping:false,alive:true,age:100}}
const fixture={version:2,pets:[pet(1),pet(2),pet(3)],food:6,available_food:{brain:false,gut:false},food_cooldowns:{brain:7,gut:7},reproduction_clock:50,egg_left:-1,egg_slot:0,final_left:25,elapsed:200,result:'',selected:1,view:'brain',notice:'Восстановление семьи',live_count:3};
fixture.pets[0].hunger=70;fixture.pets[1].hunger=0;fixture.pets[1].health=1.2;fixture.pets[2].hunger=15;fixture.pets[2].health=5;
(async()=>{
 const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--disable-dev-shm-usage','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const context=await browser.newContext({viewport:{width:1600,height:900},deviceScaleFactor:1,hasTouch:true});
 await context.addInitScript(data=>{
  if(!localStorage.getItem('rebirth-test-seeded')){
   localStorage.setItem('you-are-my-home:save:v1',JSON.stringify(data));
   localStorage.setItem('rebirth-test-seeded','yes');
  }
 },fixture);
 const page=await context.newPage();page.on('pageerror',e=>report.errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')report.errors.push(m.text())});
 const state=()=>page.evaluate(()=>structuredClone(window.__homeState));
 const click=async(x,y)=>{await page.mouse.click(x,y);await wait(180)};
 const nav=async key=>{await click({human:160,heart:430,brain:710,gut:980}[key],835);await page.waitForFunction(k=>window.__homeState?.view===k||Boolean(window.__homeState?.result),key)};
 try{
  await page.goto(process.env.HOME_TEST_URL||'http://127.0.0.1:8765/');
  await page.waitForFunction(()=>window.__homeState?.mode==='menu',null,{timeout:90000});
  await page.screenshot({path:path.join(out,'01-menu-with-save.png')});
  await click(800,290);await page.waitForFunction(()=>window.__homeState?.mode==='game');
  await page.waitForFunction(()=>window.__homeState?.pets[1]?.alive===false);
  let s=await state();
  check(s.live_count===2 && s.result==='' && !s.overlay,'junior starvation removes it without ending the game');
  check(s.final_left<0 && s.egg_left<0,'junior death resets final; Puh at or below seventy cannot lay');
  check(!s.placements.some(p=>p.id===2),'dead brain role has no rendered animation placement');
  const frozen=s.pets[1];await wait(1000);s=await state();
  check(JSON.stringify(s.pets[1])===JSON.stringify(frozen),'dead junior stats and animation age remain frozen');
  await page.screenshot({path:path.join(out,'02-empty-brain.png')});
  await click(86,660);await click(1410,220);
  await page.waitForFunction(()=>window.__homeState?.egg_slot===2 && window.__homeState?.egg_left>=0);
  s=await state();const laidAt=s.elapsed-(20-s.egg_left);report.events.push({kind:'egg',slot:2,at:laidAt});
  check(s.pets[0].hunger>70 && s.live_count===2,'feeding Puh permits a single replacement egg for the vacant brain');
  await nav('heart');await page.screenshot({path:path.join(out,'03-replacement-egg.png')});
  let gutDied=false,brainBorn=false,gutBorn=false,finalStarted=null,finalFinished=null;
  const deadline=Date.now()+165000;
  while(Date.now()<deadline){
   s=await state();if(s.result){finalFinished=s.elapsed;break}
   if(!s.pets[2].alive && !gutDied){
    gutDied=true;check(s.live_count===1 && s.result==='','both junior deaths leave a playable one-resident population');
    await nav('gut');await page.screenshot({path:path.join(out,'04-empty-gut.png')});
   }
   if(s.pets[1].alive && !brainBorn){
    brainBorn=true;const bornAt=s.elapsed-s.pets[1].age;report.events.push({kind:'hatch',slot:2,at:bornAt});
    check(Math.abs(bornAt-laidAt-20)<.25,'brain replacement hatches after twenty real simulation seconds');
    check(s.pets[1].organ==='heart' && s.pets[1].hunger>75,'replacement starts with fresh independent stats in heart');
    await click(194,660);await click(1410,685);s=await state();
    check(s.pets[1].organ==='brain' && s.placements.find(p=>p.id===2).x===112,'manual relocation restores original brain position and sprite role');
    await page.screenshot({path:path.join(out,'05-brain-restored.png')});
   }
   if(s.egg_slot===3 && !report.events.some(e=>e.kind==='egg'&&e.slot===3)){
    const at=s.elapsed-(20-s.egg_left);report.events.push({kind:'egg',slot:3,at});
    check(at-laidAt>=49.9,'next replacement egg respects at least fifty seconds between lays');
   }
   if(gutDied && s.pets[2].alive && !gutBorn){
    gutBorn=true;const at=s.elapsed-s.pets[2].age;report.events.push({kind:'hatch',slot:3,at});
    const egg=report.events.find(e=>e.kind==='egg'&&e.slot===3);
    check(egg && Math.abs(at-egg.at-20)<.25,'gut replacement also incubates twenty seconds');
    await click(302,660);await click(1410,685);s=await state();
    check(s.pets[2].organ==='gut' && s.placements.find(p=>p.id===3).y===78,'manual relocation restores original gut position');
    check(s.live_count===3 && s.final_left>35,'recovered trio starts a fresh forty-second final');
    await page.screenshot({path:path.join(out,'06-gut-restored.png')});
   }
   if(s.final_left>=0 && finalStarted===null)finalStarted=s.elapsed-(40-s.final_left);
   checkCapacity(s);
   for(const organ of ['brain','gut']){
    await nav(organ);if((await state()).result)break;
    if((await state()).available_food[organ])await click(1115,340);
   }
   s=await state();if(s.result){finalFinished=s.elapsed;break}
   for(let i=0;i<s.pets.length;i++){
    // Intentionally leave the original gut junior unfed until it dies.
    if(!s.pets[i].alive || (i===2&&!gutDied))continue;
    await click(86+i*108,660);let current=await state(),p=current.pets[i];
    if(p.hunger<78 && current.food>=3)await click(1410,220);
    if(p.energy<65&&!p.sleeping)await click(1410,450);
    if(p.energy>95&&p.sleeping)await click(1410,450);
    if(p.joy<65&&!p.sleeping){await click(190,723);await page.mouse.move(1410,336);await page.mouse.down();await wait(1000);await page.mouse.up()}
   }
   await nav('human');await wait(450);
  }
  s=await state();report.finalState=s;report.finalDuration=finalFinished-finalStarted;
  check(brainBorn&&gutBorn&&gutDied&&s.result==='win','both missing roles can be restored and reach the good ending');
  check(Math.abs(report.finalDuration-40)<.25,'restarted final runs forty seconds after recovering the trio');
  check(s.pets.map(p=>p.organ).join(',')==='heart,brain,gut','recovered roles retain their assigned organ identities');
  await click(620,535);await page.screenshot({path:path.join(out,'07-recovery-ending.png')});
  await page.reload();await page.waitForFunction(()=>window.__homeState?.mode==='menu');await click(800,290);
  await page.waitForFunction(()=>window.__homeState?.mode==='game');
  check((await state()).result==='win' && (await state()).live_count===3,'recovered population and ending survive reload');
  check(report.errors.length===0,'no Godot, resource or JavaScript errors during real recovery playthrough');
 }finally{report.lastState=await state().catch(()=>null);fs.writeFileSync(path.join(out,'rebirth-report.json'),JSON.stringify(report,null,2));await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
function checkCapacity(s){assert.ok(s.live_count+(s.egg_left>=0?1:0)<=3,'live residents plus egg capacity')}
