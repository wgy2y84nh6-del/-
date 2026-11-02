const { chromium } = require('playwright');
const fs = require('fs');
const assert = require('node:assert/strict');
const path = require('path');
const out = process.env.HOME_UI_CHECKS || path.resolve('test-results/reference');
fs.mkdirSync(`${out}/screens`, {recursive:true});
const geometry = JSON.parse(fs.readFileSync(`${out}/ui-geometry.json`));
const original = JSON.parse(fs.readFileSync(process.env.HOME_UI_FIXTURE || path.join(__dirname, 'fixtures/reference-trio.json')));
const saveKey = 'you-are-my-home:save:v1';
const report = { checks: [], errors: [], screenshots: [] };
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
function check(ok, label) { assert.ok(ok, label); report.checks.push(label); console.log('PASS:', label); }
function fixture(count) {
  const s = structuredClone(original);
  s.pets = s.pets.slice(0, count);
  s.pets.forEach((p, i) => { p.organ = ['heart', 'brain', 'gut'][i]; p.hunger = 70; p.energy = 60; p.joy = 65; p.health = 80; });
  s.live_count = count; s.selected = 0; s.view = 'heart'; s.elapsed = 0; s.result = ''; s.final_left = -1;
  s.egg_left = -1; s.egg_slot = 0; s.reproduction_clock = 0; s.notice = 'Пух уже дома. Собирай еду в мозгу и кишечнике.';
  return s;
}

(async () => {
  const browser = await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--disable-dev-shm-usage','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  async function open(data) {
    const context = await browser.newContext({viewport:{width:1600,height:900},hasTouch:true});
    if (data) await context.addInitScript(({key,data}) => {try {if(!localStorage.getItem(key)) localStorage.setItem(key,JSON.stringify(data));} catch{}}, {key:saveKey,data});
    const page = await context.newPage();
    page.on('pageerror', error => report.errors.push(String(error)));
    page.on('console', message => {if(message.type()==='error') report.errors.push(message.text());});
    await page.goto(process.env.HOME_UI_URL || 'http://127.0.0.1:18807/');
    await page.waitForFunction(()=>window.__homeState?.mode==='menu',null,{timeout:90000});
    const state = ()=>page.evaluate(()=>structuredClone(window.__homeState));
    const point = (name, scene='game') => {
      const r=geometry[scene][name],v=page.viewportSize(),s=Math.min(v.width/1600,v.height/900);
      return {x:(v.width-1600*s)/2+(r.x+r.w/2)*s,y:(v.height-900*s)/2+(r.y+r.h/2)*s};
    };
    const click = async(name,scene='game')=>{const p=point(name,scene);await page.mouse.click(p.x,p.y,{delay:30});await wait(280);};
    const screenshot = async(name)=>{await page.screenshot({path:`${out}/screens/${name}.png`});report.screenshots.push(name);};
    const start = async()=>{await click('play','menu');await page.waitForFunction(()=>window.__homeState?.mode==='game');};
    const pause = async()=>{if(!(await state()).paused) await click('pause');};
    return {context,page,state,point,click,screenshot,start,pause};
  }
  try {
    const g=await open();const {page,state,click,screenshot}=g;
    await screenshot('final-menu');
    await click('music','menu');
    check((await state()).overlay,'Menu music opens settings');
    await page.mouse.click(800,388);await page.keyboard.press('Home');await wait(180);
    check((await state()).music_volume===0,'Music artwork slider mutes music');
    await page.mouse.click(800,516);await page.keyboard.press('Home');await wait(180);
    check((await state()).effects_volume===0,'Sound artwork slider mutes effects independently');
    await page.mouse.click(800,388);await page.keyboard.press('End');
    await page.mouse.click(800,516);await page.keyboard.press('End');await wait(180);
    check((await state()).music_volume===1&&(await state()).effects_volume===1,'Both sliders restore volume');
    await screenshot('final-settings');
    await click('audio_back','settings');
    check(!(await state()).overlay,'Settings close control works');
    await click('exit','menu');await screenshot('final-exit');
    await click('exit_back','exit');
    check(!(await state()).overlay&&(await state()).mode==='menu','Exit popup returns to menu');
    await g.start();check((await state()).pets.length===1,'Supplied Play image starts game');
    await g.pause();const frozen=await state();await wait(400);
    check(Math.abs((await state()).elapsed-frozen.elapsed)<0.01,'Supplied pause icon freezes time');
    await screenshot('final-heart');
    await click('pause');check(!(await state()).paused,'Supplied play icon resumes time');
    const foodBefore=(await state()).food;await click('feed');
    check((await state()).food===foodBefore-3,'Supplied feed image costs the original three food');
    const petPoint=g.point('pet');await page.mouse.move(petPoint.x,petPoint.y);await page.mouse.down();await wait(350);
    check((await state()).petting&&(await state()).hearts===3,'Supplied pet image supports hold');
    await page.mouse.up();await wait(180);check(!(await state()).petting,'Release stops petting');
    await page.mouse.move(810,445);await page.mouse.down();await wait(200);
    check((await state()).petting,'Original direct parasite hitbox works after viewport scaling');
    await page.mouse.up();
    await click('brain');check((await state()).view==='brain','Matching missing brain button navigates correctly');
    const beforeFood=await state();await page.mouse.click(1115,335);await wait(180);
    const collected=await state();check(collected.food===beforeFood.food+1&&!collected.available_food.brain,'Original food hitbox collects exactly one');
    await page.mouse.click(1115,335);await wait(180);check((await state()).food===collected.food,'Repeated food click does not duplicate food');
    await screenshot('final-brain');
    await click('gut');check((await state()).view==='gut','Supplied gut button works');await screenshot('final-gut');
    await click('visit');check((await state()).view==='heart','Supplied visit button returns to selected pet');
    await click('sleep');check((await state()).pets[0].sleeping,'Supplied sleep image starts original sleep');
    await screenshot('final-sleep');
    const frames=new Set();for(let i=0;i<8;i++){frames.add((await state()).placements[0].frame);await wait(100);}
    check(frames.size===2,'Original two-frame sleeping animation continues');
    await click('sleep');check(!(await state()).pets[0].sleeping,'Matching wake-up control works');
    await page.waitForFunction(()=>window.__homeState.available_food.brain,null,{timeout:10000});
    check((await state()).elapsed-collected.elapsed>=6.8,'Food respawn retains the original seven-second interval');
    await click('help');check((await state()).overlay&&(await state()).paused,'Help keeps its original pause behavior');
    await screenshot('final-help');await click('help_back','help');
    await page.setViewportSize({width:1000,height:700});await wait(300);await click('human');
    check((await state()).view==='human','Scaled layout keeps mouse navigation');await screenshot('final-landscape');
    await page.setViewportSize({width:900,height:1600});await wait(300);
    const touch=g.point('gut');await page.touchscreen.tap(touch.x,touch.y);await wait(200);
    check((await state()).view==='gut','Portrait layout keeps touch navigation');await screenshot('final-portrait');
    await page.setViewportSize({width:1600,height:900});await wait(200);
    const beforeMenu=await state();await click('menu');check((await state()).mode==='menu','Matching menu button works');
    await g.start();check((await state()).food===beforeMenu.food&&(await state()).elapsed>=beforeMenu.elapsed,'Menu resume preserves the original save');
    await click('restart');await screenshot('final-restart');await click('restart_cancel','restart');await page.waitForFunction(()=>!window.__homeState.overlay);
    check(!(await state()).overlay,'Restart cancel works');
    await click('restart');await click('restart_confirm','restart');
    check((await state()).pets.length===1&&(await state()).food===6,'Restart confirm preserves original reset');
    await g.context.close();

    const trio=fixture(3);trio.pets[0].hunger=40;trio.pets[1].hunger=70;trio.pets[2].hunger=90;trio.pets[2].organ='heart';
    const t=await open(trio);await t.start();await t.pause();await t.screenshot('final-card-puh');
    await t.click('family1');check((await t.state()).selected===1,'Supplied Lilu selector works');await t.screenshot('final-card-lilu');
    await t.click('family2');check((await t.state()).selected===2,'Supplied Rostik selector works');await t.screenshot('final-card-rostik');
    await t.click('pause');await t.click('move');
    check((await t.state()).pets[2].organ==='gut','Matching relocation button preserves original Rostik role');
    await t.click('visit');check((await t.state()).view==='gut','Visit follows relocated pet');
    await t.pause();await t.click('human');await t.screenshot('final-human-stage3');await t.context.close();
    const two=await open(fixture(2));await two.start();await two.pause();await two.click('human');await two.screenshot('final-human-stage2');
    check((await two.state()).live_count===2,'Second human-stage image corresponds to two living pets');await two.context.close();
    const egg=fixture(1);egg.egg_left=10;egg.egg_slot=2;
    const e=await open(egg);await e.start();await e.pause();await e.screenshot('final-egg');check((await e.state()).egg_left>9,'Egg timer state remains visible');await e.context.close();
    const dead=fixture(3);dead.pets[1].health=0;dead.pets[1].alive=false;
    const d=await open(dead);await d.start();await d.pause();await d.click('brain');await d.screenshot('final-junior-death');
    const deadState=await d.state();check(deadState.live_count===2&&deadState.result===''&&!deadState.placements.some(p=>p.id===2),'Dead junior has no sprite and game continues');await d.context.close();
    const win=fixture(3);win.result='win';win.notice='Человек умер. Все трое живы — теперь это ваш дом.';win.final_left=0;
    const w=await open(win);await w.start();await w.screenshot('final-win');
    check((await w.state()).result==='win'&&(await w.state()).overlay,'Original win uses matching modal');await w.click('ending_look','win');await w.screenshot('final-win-art');await w.context.close();
    const loss=fixture(1);loss.result='loss';loss.pets[0].health=0;loss.pets[0].alive=false;loss.notice='Пух погиб. В следующий раз не оставляй его голодным.';
    const l=await open(loss);await l.start();await l.screenshot('final-loss');
    check((await l.state()).result==='loss'&&(await l.state()).overlay,'Original loss uses matching modal');await l.click('ending_again','loss');
    check((await l.state()).result===''&&(await l.state()).pets[0].alive,'Ending restart remains functional');await l.context.close();
    check(report.errors.length===0,'No browser, JavaScript, Godot or missing-resource errors');
  } finally {
    fs.writeFileSync(`${out}/browser-ui.json`,JSON.stringify(report,null,2));
    await browser.close();
  }
  console.log(`RESULT: ${report.checks.length} browser checks, ${report.errors.length} errors, ${report.screenshots.length} screenshots`);
})().catch(error=>{console.error(error);process.exitCode=1});
