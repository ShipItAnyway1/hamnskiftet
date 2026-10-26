#!/usr/bin/env node
'use strict';
// Exercises the shipped canvas through real mobile touch. IndexedDB is read-only
// evidence of Godot's actual user:// save, never a control/debug bridge.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
function option(name, fallback) {
 const at = process.argv.indexOf(name);
 return at >= 0 ? process.argv[at + 1] : fallback;
}
const url = option('--url', process.env.BASE_URL || 'http://127.0.0.1:8765/');
const output = path.resolve(option('--output-dir', 'ci-results/browser'));
fs.mkdirSync(output, { recursive: true });
const evidence = {url, emulation:{width:390,height:844,dpr:1,hasTouch:true,isMobile:true}, console:[], pageErrors:[], responses:[], requestFailures:[], checks:[], saves:[]};
const persist = () => fs.writeFileSync(path.join(output,'evidence.json'), JSON.stringify(evidence,null,2));
let browser;
let phase = 'boot';
async function readSave(page) {
 return page.evaluate(async () => {
  const databases = await indexedDB.databases();
  for (const info of databases) {
   const db = await new Promise((resolve,reject) => {const q=indexedDB.open(info.name);q.onsuccess=()=>resolve(q.result);q.onerror=()=>reject(q.error);});
   try {
    if (!db.objectStoreNames.contains('FILE_DATA')) continue;
    const records = await new Promise((resolve,reject) => {
     const store=db.transaction('FILE_DATA','readonly').objectStore('FILE_DATA');
     const q=store.getAllKeys();q.onerror=()=>reject(q.error);
     q.onsuccess=()=>{
      const keys=q.result.filter(key=>String(key).endsWith('/hamnskiftet.cfg'));
      if(!keys.length){resolve([]);return;}
      const reads=keys.map(key=>new Promise((done,fail)=>{const r=store.get(key);r.onsuccess=()=>done({key,value:r.result});r.onerror=()=>fail(r.error);}));
      Promise.all(reads).then(resolve,reject);
     };
    });
    for(const record of records) {
     const bytes=record.value?.contents;
     if(bytes) return {database:info.name,key:String(record.key),text:typeof bytes==='string'?bytes:new TextDecoder().decode(new Uint8Array(bytes))};
    }
   } finally { db.close(); }
  }
  return null;
 });
}
async function pollSave(page, predicate, description) {
 const deadline=Date.now()+30000;
 let saved;
 while(Date.now()<deadline) {
  saved=await readSave(page);
  if(saved && predicate(saved.text)) return saved;
  await page.waitForTimeout(500);
 }
 throw new Error(description+' (no matching persisted save within30s; last='+String(saved?.text).slice(0,180)+')');
}
function statuses(text) {return [...text.matchAll(/"status"\s*:\s*"([^"]+)"/g)].map(match=>match[1]);}
function activeStageOne(text) {return /\[campaign\]/.test(text)&&/"stage"\s*:\s*1\b/.test(text)&&statuses(text).some(status=>status!=='yard');}
function muted(text) {const settings=text.split('[settings]')[1]||'';return /\bsound\s*=\s*false\b/.test(settings)&&/\bmusic\s*=\s*false\b/.test(settings);}
function recordSave(name, saved) {
 fs.writeFileSync(path.join(output,name+'.cfg'),saved.text);
 evidence.saves.push({name,database:saved.database,key:saved.key,statuses:statuses(saved.text),muted:muted(saved.text),activeStageOne:activeStageOne(saved.text)});
 persist();
}
async function check(name, operation) {
 await operation();evidence.checks.push(name);persist();console.log('PASS '+name);
}
(async()=>{
 const launch={headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--enable-webgl','--disable-dev-shm-usage']};
 if(process.env.PLAYWRIGHT_EXECUTABLE_PATH) launch.executablePath=process.env.PLAYWRIGHT_EXECUTABLE_PATH;
 browser=await chromium.launch(launch);
 const context=await browser.newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true,deviceScaleFactor:1});
 const page=await context.newPage();
 page.on('console',message=>{evidence.console.push({phase,type:message.type(),text:message.text()});persist();});
 page.on('pageerror',error=>{evidence.pageErrors.push({phase,error:String(error)});persist();});
 page.on('response',response=>{evidence.responses.push({phase,url:response.url(),status:response.status()});persist();});
 page.on('requestfailed',request=>{evidence.requestFailures.push({phase,url:request.url(),error:request.failure()});persist();});
 const screenshot=name=>page.screenshot({path:path.join(output,name+'.png')});
 const boot=async()=>{
  await page.locator('#play').tap();
  await page.waitForFunction(()=>document.documentElement.dataset.gameReady==='true',null,{timeout:120000});
  await page.waitForTimeout(1500);
  assert.equal(await page.locator('#launch').count(),0,'Launch shell must hand over to native canvas');
 };
 await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});
 await screenshot('00-launch');
 await check('shell Spela starts real Godot canvas',boot);
 await screenshot('01-harbor-menu');
 phase='real-touch';
 await page.touchscreen.tap(195,674); // Actual Spela bana1 button, inside letterboxed900×1440 canvas.
 await page.waitForTimeout(1000);
 await page.touchscreen.tap(125,425); // Visible north-facing green truck in stage1.
 await page.waitForTimeout(2200);
 await screenshot('02-truck-touch-and-road');
 await check('real truck touch persists a non-yard stage1 truck',async()=>{
  const saved=await pollSave(page,activeStageOne,'Touch must dispatch an actual truck');recordSave('save-after-touch',saved);
 });
 phase='pause-settings';
 await page.touchscreen.tap(361,136);
 await page.waitForTimeout(300);
 await screenshot('03-paused');
 await page.touchscreen.tap(105,536); // Real effects button.
 await page.waitForTimeout(150);
 await page.touchscreen.tap(265,536); // Real music button.
 await page.waitForTimeout(150);
 await check('actual pause buttons persist both sound settings off',async()=>{
  const saved=await pollSave(page,text=>activeStageOne(text)&&muted(text),'Mute buttons must reach actual ConfigFile settings');recordSave('save-before-reload',saved);
 });
 await screenshot('04-muted-settings');
 phase='reload';
 await page.reload({waitUntil:'domcontentloaded'});
 await check('reload launches without losing persisted state',boot);
 await screenshot('05-reloaded-harbor');
 await check('IndexedDB retains real stage1 truck and mute settings after reload',async()=>{
  const saved=await pollSave(page,text=>activeStageOne(text)&&muted(text),'Reload must preserve active campaign and sound settings');recordSave('save-after-reload',saved);
 });
 phase='resume';
 await page.touchscreen.tap(195,674); // Actual Fortsätt bana1, same primary action.
 await page.waitForTimeout(800);
 await screenshot('06-resumed-stage');
 await page.touchscreen.tap(361,136);
 await page.waitForTimeout(300);
 await screenshot('07-resumed-pause');
 const fatalConsole=evidence.console.filter(message=>message.type==='error'||/SCRIPT ERROR|Missing local audio|ERROR:|ResourceLoader.*(?:error|failed)/i.test(message.text));
 const badResponses=evidence.responses.filter(response=>response.status>=400);
 evidence.fatalConsole=fatalConsole;evidence.badResponses=badResponses;
 assert.deepEqual(evidence.pageErrors,[],'No browser runtime exceptions');
 assert.deepEqual(evidence.requestFailures,[],'No failed network requests');
 assert.deepEqual(badResponses,[],'No HTTP4xx/5xx asset responses');
 assert.deepEqual(fatalConsole,[],'No Godot/script/audio/resource errors');
 evidence.ok=true;persist();
 console.log('WEB_BROWSER_SMOKE_OK: real mobile touch dispatch, pause mute, IndexedDB save/reload, no runtime/resource/network errors');
})().catch(error=>{
 evidence.ok=false;evidence.failure=String(error.stack||error);persist();console.error(error);process.exitCode=1;
}).finally(async()=>{if(browser)await browser.close();persist();});
