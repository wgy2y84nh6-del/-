// Real exported WASM, real pointer actions, real 50 / 20 / 40 second timers.
// npm install playwright (outside the project) if not already provided.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const assert = require('node:assert/strict');
const out = process.env.HOME_TEST_OUTPUT || '/tmp/home-browser-results';
fs.mkdirSync(out, { recursive: true });
const wait = ms => new Promise(r => setTimeout(r, ms));
const report = { checks: [], errors: [], events: [] };
function check(ok, text) { assert.ok(ok, text); report.checks.push(text); console.log('PASS:', text); }

(async () => {
  const browser = await chromium.launch({executablePath: '/usr/bin/chromium', headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']});
  const context = await browser.newContext({ viewport: {width:1600,height:900}, deviceScaleFactor: 1, hasTouch: true });
  const page = await context.newPage();
  page.on('pageerror', e => report.errors.push(String(e)));
  page.on('console', m => { if (m.type()==='error') report.errors.push(m.text()); });
  const state = () => page.evaluate(() => structuredClone(window.__homeState));
  const click = async (x,y) => { await page.mouse.click(x,y); await wait(160); };
  const nav = async key => {
    await click({human:160,heart:430,brain:710,gut:980}[key],835);
    await page.waitForFunction(k => window.__homeState?.view === k || Boolean(window.__homeState?.result), key);
  };
  try {
    await page.goto(process.env.HOME_TEST_URL || 'http://127.0.0.1:8765/',{waitUntil:'load'});
    await page.waitForFunction(() => window.__homeState?.mode === 'menu', {timeout:90000});
    await page.screenshot({path:path.join(out,'01-menu.png')});
    check(true, 'WASM loads and main menu renders');
    await click(800,290);
    await page.waitForFunction(() => window.__homeState?.mode === 'game');
    let s = await state();
    check(s.pets.length===1 && s.view==='heart', 'game starts with one resident in heart');
    await page.screenshot({path:path.join(out,'02-heart.png')});
    const frames=new Set();
    for (let i=0;i<12;i++) { frames.add((await state()).placements[0].frame); await wait(100); }
    check(frames.size===2, 'awake animation alternates two frames in browser');
    let food=s.food;
    await nav('brain');
    await click(1115,340);
    s=await state();
    check(s.food===food+1 && s.available_food.brain===false, 'food disappears and adds exactly +1 in brain');
    await click(1115,340);
    check((await state()).food===food+1, 'repeated click cannot collect same food');
    await nav('gut');
    s=await state();
    check(s.available_food.gut, 'unclicked gut food survives navigation');
    await click(1115,340);
    check((await state()).food===food+2, 'gut food also adds exactly +1');
    await nav('heart');
    const beforeFeed=await state();
    await click(1410,220);
    s=await state();
    check(s.food===beforeFeed.food-3 && s.pets[0].hunger>beforeFeed.pets[0].hunger, 'feed button costs three and restores hunger');
    const beforeWash=s.pets[0].clean;
    await click(1410,296);
    check((await state()).pets[0].clean>beforeWash, 'wash button restores clean');
    await page.mouse.move(1410,374); await page.mouse.down(); await wait(550);
    s=await state();
    check(s.petting && s.hearts===3, 'holding pet button shows exactly three hearts');
    await page.screenshot({path:path.join(out,'03-petting.png')});
    await page.mouse.up(); await wait(150);
    check(!(await state()).petting && (await state()).hearts===0, 'release immediately removes hearts');
    await page.mouse.move(806,440); await page.mouse.down(); await wait(200);
    check((await state()).petting, 'direct resident press starts petting');
    await page.mouse.move(1598,750); await page.mouse.up(); await wait(160);
    check(!(await state()).petting, 'release outside resident also stops hearts');
    await click(1410,450);
    s=await state(); const energy=s.pets[0].energy;
    const sleepFrames=new Set();
    for(let i=0;i<12;i++){sleepFrames.add((await state()).placements[0].frame);await wait(100);}
    check((await state()).pets[0].sleeping && (await state()).pets[0].energy>energy && sleepFrames.size===2, 'sleep button restores energy and alternates sleep frames');
    await nav('human');
    await wait(400);
    check((await state()).pets[0].sleeping, 'sleep continues on human screen');
    await click(1410,450);
    check(!(await state()).pets[0].sleeping, 'resident can be awakened from another screen');
    await click(860,47); const frozen=await state(); await wait(850); s=await state();
    check(s.paused && Math.abs(s.elapsed-frozen.elapsed)<.01, 'pause freezes game timers');
    await click(860,47);
    const startElapsed=(await state()).elapsed;
    for(let i=0;i<6;i++) for(const organ of ['human','heart','brain','gut']) await nav(organ);
    s=await state();
    check(s.elapsed>startElapsed+3 && s.placements[0].x===112 && s.placements[0].y===42, '24 repeated navigations keep simulation active and resident anchored');
    // Touch uses the Godot touch-to-mouse route, not direct model commands.
    await page.touchscreen.tap(710,835); await wait(200);
    check((await state()).view==='brain', 'touch navigation opens brain');
    if ((await state()).available_food.brain) {
      const n=(await state()).food;
      await page.touchscreen.tap(1115,340); await wait(200);
      check((await state()).food===n+1 && !(await state()).available_food.brain, 'touch collects food exactly once');
    }
    // Resize while running, then restore the reference layout.
    await page.setViewportSize({width:1000,height:700}); await wait(300);
    await page.screenshot({path:path.join(out,'04-resize.png')});
    await page.setViewportSize({width:1600,height:900}); await wait(200);
    check((await state()).mode==='game', 'resize preserves running state');
    let lastCount=1, capturedEgg=false, finalStarted=null, finalFinished=null;
    const deadline=Date.now()+210000;
    // Full playthrough using only GUI input. No game speed modification.
    while (Date.now()<deadline) {
      s=await state();
      if(s.result){finalFinished=s.elapsed;break;}
      if(s.egg_left>=0 && !capturedEgg){await nav('heart'); await page.screenshot({path:path.join(out,'05-egg.png')});capturedEgg=true;}
      if(s.pets.length!==lastCount){
        report.events.push({kind:'hatch',count:s.pets.length,at:s.elapsed,final:s.final_left});
        lastCount=s.pets.length;
      }
      if(s.final_left>=0 && finalStarted===null) finalStarted=s.elapsed-(40-s.final_left);
      for (const organ of ['brain','gut']) {
        await nav(organ);
        if((await state()).result) break;
        if((await state()).available_food[organ]) await click(1115,340);
      }
      s=await state();
      if(s.result){finalFinished=s.elapsed;break;}
      for(let i=0;i<s.pets.length;i++) {
        await click(86+i*108,660);
        let current=await state(), p=current.pets[i];
        if(p.hunger<72 && current.food>=3) await click(1410,220);
        if(p.clean<72) await click(1410,296);
        if(p.energy<68 && !p.sleeping) await click(1410,450);
        if(p.energy>96 && p.sleeping) await click(1410,450);
        if(p.joy<70 && !p.sleeping) {
          await click(190,723);
          await page.mouse.move(1410,374); await page.mouse.down();await wait(900);await page.mouse.up();
        }
        if(i>0 && p.organ==='heart') {
          await click(1410,685);
          const moved=await state();
          check(moved.pets[i].organ===(i===1?'brain':'gut'), 'resident '+(i+1)+' relocates manually to correct organ');
          check(moved.placements[i].x===112 && moved.placements[i].y===(i===1?42:78), 'resident '+(i+1)+' occupies reference anchor after relocation');
          await page.screenshot({path:path.join(out,i===1?'06-brain.png':'07-gut.png')});
        }
      }
      await nav('human');
      if(lastCount>=2) await page.screenshot({path:path.join(out,'human-stage-'+lastCount+'.png')});
      await wait(600);
    }
    s=await state();
    check(s.result==='win' && s.pets.length===3 && s.pets.every(p=>p.alive), 'full browser playthrough reaches good ending with all three alive');
    check(finalStarted!==null && Math.abs(finalFinished-finalStarted-40)<.25, 'browser final timer runs for actual forty simulation seconds');
    report.finalDuration=finalFinished-finalStarted;
    report.finishedAt=finalFinished;
    check(s.pets.map(p=>p.organ).join(',')==='heart,brain,gut', 'all three residents remain in assigned homes at ending');
    check(s.egg_left<0, 'no extra egg or fourth resident');
    check(s.music_stage===3 && s.music_playing, 'stage-three music is playing at ending');
    await click(620,535);
    await page.screenshot({path:path.join(out,'08-ending.png')});
    await page.reload({waitUntil:'load'});
    await page.waitForFunction(()=>window.__homeState?.mode==='menu');
    await click(800,290);
    await page.waitForFunction(()=>window.__homeState?.mode==='game');
    s=await state();
    report.restoredState=s;
    check(s.result==='win' && s.pets.length===3, 'browser save survives page reload');
    check(report.errors.length===0, 'no browser JavaScript/Godot errors during full playthrough');
  } finally {
    report.lastState=await state().catch(()=>null);
    fs.writeFileSync(path.join(out,'browser-report.json'),JSON.stringify(report,null,2));
    await browser.close();
  }
})().catch(e=>{console.error(e);process.exitCode=1});
