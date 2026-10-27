#!/usr/bin/env node
'use strict';
// Exercises the shipped canvas through real mobile touch. IndexedDB is read-only
// evidence of Godot's actual user:// save, never a control/debug bridge.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const zlib = require('node:zlib');
function option(name, fallback) {
 const at = process.argv.indexOf(name);
 return at >= 0 ? process.argv[at + 1] : fallback;
}
const url = option('--url', process.env.BASE_URL || 'http://127.0.0.1:8765/');
const output = path.resolve(option('--output-dir', 'ci-results/browser'));
fs.mkdirSync(output, { recursive: true });
const width=Number(option('--width','390'));
const height=Number(option('--height','844'));
const dpr=Number(option('--dpr','1'));
assert.ok(dpr>=1&&dpr<=4,'DPR between1and4');
const layoutOnly=process.argv.includes('--layout-only');
const safeInsets={top:Number(option('--safe-top','0')),bottom:Number(option('--safe-bottom','0')),left:Number(option('--safe-left','0')),right:Number(option('--safe-right','0'))};
for(const value of [width,height,...Object.values(safeInsets)]) assert.ok(Number.isFinite(value)&&value>=0,'Valid viewport/inset argument');
assert.ok(width>0&&height>0,'Positive viewport dimensions');
const evidence = {url, emulation:{width,height,dpr,hasTouch:true,isMobile:true,safeInsets}, console:[], pageErrors:[], responses:[], requestFailures:[], checks:[], saves:[], savePolls:[], touches:[], inputEvents:[], environments:[], layouts:[], layoutAudits:[], gestures:[]};
const persist = () => fs.writeFileSync(path.join(output,'evidence.json'), JSON.stringify(evidence,null,2));
let browser;
let page;
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
 // Web IDBFS writes are asynchronous. A software-rendered CI frame can take
 // seconds; observe persistence separately from the already-observed UI action.
 const started=Date.now(),budgetMs=120000;
 let saved,attempts=0,lastSignature;
 const observe=(match,outcome)=>{
  const currentStatuses=saved?statuses(saved.text):[];
  const signature=JSON.stringify([Boolean(saved),currentStatuses,match]);
  if(signature!==lastSignature||outcome) {
   evidence.savePolls.push({phase,description,elapsedMs:Date.now()-started,statuses:currentStatuses,match,attempts,...(outcome?{outcome}:{})});
   lastSignature=signature;persist();
  }
 };
 while(Date.now()-started<budgetMs) {
  saved=await readSave(page);attempts++;
  const match=Boolean(saved&&predicate(saved.text));
  observe(match,match?'matched':undefined);
  if(match)return saved;
  await page.waitForTimeout(500);
 }
 observe(false,'timeout');
 if(saved)recordSave('failure-before-timeout',saved);
 evidence.failedPredicate={phase,description,budgetMs,elapsedMs:Date.now()-started,attempts};persist();
 throw new Error(description+' (no matching persisted save within120s; last='+String(saved?.text).slice(0,180)+')');
}
function statuses(text) {return [...text.matchAll(/"status"\s*:\s*"([^"]+)"/g)].map(match=>match[1]);}
function activeStageOne(text) {return /\[campaign\]/.test(text)&&/"stage"\s*:\s*1\b/.test(text)&&statuses(text).some(status=>status!=='yard');}
function setting(text, key) {
 const section=text.split('[settings]')[1]||'';
 const match=section.match(new RegExp('\\b'+key+'\\s*=\\s*(true|false)\\b'));
 return match ? match[1]==='true' : null;
}
function muted(text) {return setting(text,'sound')===false&&setting(text,'music')===false;}
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
 const context=await browser.newContext({viewport:{width,height},hasTouch:true,isMobile:true,deviceScaleFactor:dpr});
 await context.addInitScript(()=>{
  // Passive, capture-only observation: never cancel, synthesize or modify input.
  for(const type of ['touchstart','touchend','touchcancel','pointerdown','pointerup','mousedown','mouseup','click']) {
   document.addEventListener(type,event=>{
    const points=Array.from(event.changedTouches||[]).map(touch=>({id:touch.identifier,x:touch.clientX,y:touch.clientY,force:touch.force}));
    console.debug('__BROWSER_SMOKE_INPUT__'+JSON.stringify({
     type:event.type,eventClass:event.constructor.name,isTrusted:event.isTrusted,
     at:new Date().toISOString(),timeStamp:event.timeStamp,
     x:event.clientX,y:event.clientY,button:event.button,buttons:event.buttons,
     pointerType:event.pointerType,pointerId:event.pointerId,
     sourceFiresTouch:event.sourceCapabilities?.firesTouchEvents,
     target:{tag:event.target?.tagName,id:event.target?.id},points
    }));
   },{capture:true,passive:true});
  }
 });
 page=await context.newPage();
 page.setDefaultTimeout(120000);
 const cdp=await context.newCDPSession(page);
 if(Object.values(safeInsets).some(value=>value>0)) {
  await cdp.send('Emulation.setSafeAreaInsetsOverride',{insets:safeInsets});
 }
 const renderedFrames=async()=>{
  // Browser RAF shares the main loop with Godot. Two callbacks span a real
  // engine frame even on a heavily throttled software-rendering CI runner.
  let timer;
  try {
   await Promise.race([
    page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve())))),
    new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('No rendered frame within120s')),120000);})
   ]);
  } finally {clearTimeout(timer);}
 };
 const touch=async(x,y,label)=>{
  const started=Date.now();
  const entry={phase,label,x,y,method:'CDP touch held across rendered frames',started:new Date().toISOString()};
  evidence.touches.push(entry);persist();
  try {
   await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y,id:1,radiusX:1,radiusY:1,force:1}]});
   await renderedFrames();
  } finally {
   await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  }
  await renderedFrames();
  entry.elapsedMs=Date.now()-started;persist();
 };
 page.on('console',message=>{
  const text=message.text();
  if(text.startsWith('__BROWSER_SMOKE_INPUT__')) {
   try {evidence.inputEvents.push({phase,...JSON.parse(text.slice('__BROWSER_SMOKE_INPUT__'.length))});}
   catch(error){evidence.inputEvents.push({phase,parseError:String(error),text});}
  } else {evidence.console.push({phase,type:message.type(),text});}
  persist();
 });
 page.on('pageerror',error=>{evidence.pageErrors.push({phase,error:String(error)});persist();});
 page.on('response',response=>{evidence.responses.push({phase,url:response.url(),status:response.status()});persist();});
 page.on('requestfailed',request=>{evidence.requestFailures.push({phase,url:request.url(),error:request.failure()});persist();});
 const screenshot=name=>page.screenshot({scale:'css',path:path.join(output,name+'.png')});
 const environment=async(label)=>{
  const actual=await page.evaluate(()=>{
   const canvas=document.getElementById('canvas');
   const rect=canvas?.getBoundingClientRect();
   return {userAgent:navigator.userAgent,platform:navigator.platform,maxTouchPoints:navigator.maxTouchPoints,
    dpr:devicePixelRatio,innerWidth,innerHeight,screen:{width:screen.width,height:screen.height},
    visualViewport:visualViewport?{width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale,offsetLeft:visualViewport.offsetLeft,offsetTop:visualViewport.offsetTop}:null,
    canvas:canvas?{width:canvas.width,height:canvas.height,css:rect?.toJSON()}:null,
    visibility:document.visibilityState};
  });
  evidence.environments.push({phase,label,at:new Date().toISOString(),...actual});persist();
 };
 const readLayout=async(predicate=()=>true)=>{
  const deadline=Date.now()+120000;
  let layout;
  while(Date.now()<deadline) {
   layout=await page.evaluate(()=>{
    const node=document.getElementById('game-layout');
    if(!node?.textContent)return null;
    try{return JSON.parse(node.textContent);}catch{return null;}
   });
   if(layout?.version===1&&layout.viewport?.w>0&&layout.viewport?.h>0&&predicate(layout))return layout;
   await page.waitForTimeout(100);
  }
  throw new Error('Read-only game-layout v1 did not satisfy current visible layout: '+JSON.stringify(layout).slice(0,300));
 };
 const canvasRect=async()=>page.locator('#canvas').boundingBox();
 const toCss=(point,layout,canvas)=>({x:canvas.x+point[0]*canvas.width/layout.viewport.w,y:canvas.y+point[1]*canvas.height/layout.viewport.h});
 const cssRect=(rect,layout,canvas)=>{const p=toCss(rect,layout,canvas);return {...p,width:rect[2]*canvas.width/layout.viewport.w,height:rect[3]*canvas.height/layout.viewport.h};};
 const controlReady=(layout,key)=>layout.controls?.[key]?.visible&&!layout.controls[key].disabled&&!layout.controls[key].clipped;
 const touchControl=async(key,label)=>{
  const layout=await readLayout(value=>controlReady(value,key));
  const control=layout.controls[key];
  const rect=control.rect;
  assert.ok(Array.isArray(rect)&&rect.length===4,'Actual control rectangle: '+key);
  const canvas=await canvasRect();
  const point=toCss([rect[0]+rect[2]*.5,rect[1]+rect[3]*.5],layout,canvas);
  await touch(point.x,point.y,label||key);
 };
 const touchVehicle=async(id)=>{
  const layout=await readLayout(value=>value.screen==='game'&&controlReady(value,'pause')&&value.vehicles?.some(vehicle=>vehicle.id===id&&Array.isArray(vehicle.pick)));
  const vehicle=layout.vehicles.find(item=>item.id===id);
  const point=toCss(vehicle.pick,layout,await canvasRect());
  await touch(point.x,point.y,'dispatch-visible-truck-'+id);
 };
 const testGestures=async(restore=true)=>{
  const before=await readLayout(value=>value.screen==='game'&&value.camera&&value.regions?.yard);
  const ids=before.vehicles.map(item=>item.id).sort((a,b)=>a-b);
  const pinch=async(fromSpread,toSpread,label)=>{
   const layout=await readLayout(value=>value.screen==='game'&&value.camera);
   const area=layout.regions.yard,canvas=await canvasRect();
   const points=spread=>[-1,1].map((side,index)=>{
    const point=toCss([area[0]+area[2]*(.5+side*spread),area[1]+area[3]*.5],layout,canvas);
    return {...point,id:index+1,radiusX:1,radiusY:1,force:1};
   });
   evidence.gestures.push({label,before:layout.camera,from:points(fromSpread),to:points(toSpread)});persist();
   try {
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:points(fromSpread)});
    await renderedFrames();
    await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:points(toSpread)});
    await renderedFrames();
   } finally {await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});}
   await renderedFrames();
  };
  await pinch(.15,.24,'two-finger-zoom-in');
  const zoomed=await readLayout(value=>value.camera?.zoom>1.15);
  evidence.gestures[evidence.gestures.length-1].after=zoomed.camera;persist();
  await screenshot('gesture-zoomed');
  const area=zoomed.regions.yard,canvas=await canvasRect();
  const point=fraction=>{const css=toCss([area[0]+area[2]*fraction[0],area[1]+area[3]*fraction[1]],zoomed,canvas);return {...css,id:1,radiusX:1,radiusY:1,force:1};};
  const panEnd=restore?[.62,.57]:[.9,.88];
  try {
   await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point([.5,.5])]});
   await renderedFrames();
   await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[point(panEnd)]});
   await renderedFrames();
  } finally {await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});}
  await renderedFrames();
  const moved=await readLayout(value=>value.camera&&Math.hypot(value.camera.pan[0]-zoomed.camera.pan[0],value.camera.pan[1]-zoomed.camera.pan[1])>.01);
  evidence.gestures.push({label:'one-finger-pan',before:zoomed.camera,after:moved.camera});persist();
  await screenshot('gesture-panned');
  if(!restore) {
   assert.deepEqual(moved.vehicles.map(item=>item.id).sort((a,b)=>a-b),ids,'Zoom/pan do not dispatch parked vehicles');
   return;
  }
  await pinch(.24,.12,'two-finger-return-to-fit');
  const fitted=await readLayout(value=>value.camera?.zoom<=1.01&&Math.hypot(...value.camera.pan)<.01);
  evidence.gestures[evidence.gestures.length-1].after=fitted.camera;persist();
  assert.deepEqual(fitted.vehicles.map(item=>item.id).sort((a,b)=>a-b),ids,'Pinch/pan must never dispatch another parked truck');
  await screenshot('gesture-restored-fit');
 };
 const auditLayout=async(label,expectedSize)=>{
  const canvas=await canvasRect();
  const layout=await readLayout(value=>Math.abs(value.viewport.w/value.viewport.h-canvas.width/canvas.height)<.003);
  const buffer=await page.evaluate(()=>{const canvas=document.getElementById('canvas');return {width:canvas.width,height:canvas.height};});
  const audit={label,buffer,at:new Date().toISOString(),viewport:layout.viewport,canvas,mode:layout.mode,controls:[],vehicles:[],cargo:[]};
  evidence.layouts.push({label,...layout});
  evidence.layoutAudits.push(audit);persist();
  assert.ok(Math.abs(canvas.x-safeInsets.left)<=2&&Math.abs(canvas.y-safeInsets.top)<=2,'Canvas honors top/left safe area');
  const browserSize=expectedSize||page.viewportSize();
  assert.ok(Math.abs(canvas.width-(browserSize.width-safeInsets.left-safeInsets.right))<=2&&Math.abs(canvas.height-(browserSize.height-safeInsets.top-safeInsets.bottom))<=2,'Canvas fills available screen without fixed aspect letterboxing');
  assert.ok(Math.abs(layout.viewport.w/layout.viewport.h-canvas.width/canvas.height)<.003,'Logical root viewport matches real canvas aspect');
  assert.ok(buffer.width<=canvas.width*2.05+2&&buffer.height<=canvas.height*2.05+2,'Retina drawing buffer respects2xperformancecap');
  const screen=layout.screen||(layout.controls?.harbor_play?.visible?'harbor':layout.controls?.modal_continue?.visible?'pause':'game');
  const fallbackKeys=screen==='harbor'?['harbor_play']:screen==='pause'?['modal_continue','effects','music','paid_undo','restart','test_toggle','pause_harbor']:['pause','rescue','cargo_legend'];
  const seenControls=new Set();
  for(const [key,control] of Object.entries(layout.controls||{})) {
   if(!control.visible||control.disabled)continue;
   if(control.clipped){audit.clippedControls=(audit.clippedControls||0)+1;continue;}
   if(!layout.screen&&!fallbackKeys.includes(key))continue;
   const rect=cssRect(control.rect,layout,canvas);
   const identity=control.path||control.rect.map(value=>Number(value).toFixed(3)).join(',');
   if(seenControls.has(identity))continue;
   seenControls.add(identity);
   audit.controls.push({key,...rect});
   assert.ok(rect.width>=43.5&&rect.height>=43.5,`${label}:${key} touch target is ${rect.width.toFixed(1)}×${rect.height.toFixed(1)} CSSpx, requires44`);
   assert.ok(rect.x>=canvas.x-1&&rect.y>=canvas.y-1&&rect.x+rect.width<=canvas.x+canvas.width+1&&rect.y+rect.height<=canvas.y+canvas.height+1,`${label}:${key} inside safe visible canvas`);
  }
  assert.ok(audit.controls.length>0,'Visible screen has audited touch controls');
  for(let i=0;i<audit.controls.length;i++)for(let j=i+1;j<audit.controls.length;j++) {
   const a=audit.controls[i],b=audit.controls[j];
   const overlapW=Math.min(a.x+a.width,b.x+b.width)-Math.max(a.x,b.x);
   const overlapH=Math.min(a.y+a.height,b.y+b.height)-Math.max(a.y,b.y);
   assert.ok(overlapW<=1||overlapH<=1,`${label}:interactive buttons ${a.key}/${b.key} overlap`);
  }
  for(const kind of ['vehicles','cargo'])for(const item of layout[kind]||[]) {
   const measured={id:item.id,kind:item.kind};
   if(item.rect)measured.body=cssRect(item.rect,layout,canvas);
   if(item.glyph_rect)measured.glyph=cssRect(item.glyph_rect,layout,canvas);
   audit[kind].push(measured);
  }
  if(layout.camera?.zoom>1.01&&Array.isArray(layout.camera.pan)&&layout.regions?.yard) {
   const base=layout.camera.yard_size*layout.camera.zoom,area=layout.regions.yard;
   const allowance=[base*area[2]/area[3],base].map(value=>value*(1-1/layout.camera.zoom)*.53);
   audit.camera={...layout.camera,maximumPan:allowance};
   assert.ok(Math.abs(layout.camera.pan[0])<=allowance[0]+.01&&Math.abs(layout.camera.pan[1])<=allowance[1]+.01,'Zoomed camera pan remains inside resized viewport bounds');
  }
  const image=await page.screenshot({scale:'css',path:path.join(output,label+'.png')});
  audit.blackEdgeBands=blackEdgeBands(image);
  audit.regionPixels={};
  const modal=layout.regions?.modal?cssRect(layout.regions.modal,layout,canvas):null;
  for(const key of ['dock','yard','road']) {
   if(!layout.regions?.[key])continue;
   const rect=cssRect(layout.regions[key],layout,canvas);
   const metrics=regionPixels(image,rect,screen==='pause'?modal:null);
   audit.regionPixels[key]=metrics;
   if(screen==='game'||(screen==='pause'&&key==='road'&&modal)) {
    assert.ok(metrics.samples>=200&&metrics.colorBins>=3&&metrics.dominantFraction<.995,`${label}:${key} frozen/resized viewport appears blank: ${JSON.stringify(metrics)}`);
   }
  }
  assert.ok(Object.values(audit.blackEdgeBands).every(value=>value<=2),label+' has black letterbox bands: '+JSON.stringify(audit.blackEdgeBands));
  persist();
  console.log('PASS responsive layout '+label+' '+JSON.stringify({canvas,mode:layout.mode,controls:audit.controls.length}));
 };
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
 await environment('harbor-ready');
 await auditLayout('layout-harbor');
 phase='real-touch';
 await touchControl('harbor_play','start-stage1'); // Actual current rendered primary button.
 await readLayout(value=>value.screen==='game'&&controlReady(value,'pause'));
 await auditLayout('layout-stage');
 await touchVehicle(2); // Same actual stage1 truck as before; only its observed projection changes.
 await check('real truck touch removes truck2 from the observed yard',async()=>{
  const layout=await readLayout(value=>value.screen==='game'&&controlReady(value,'pause')&&Array.isArray(value.vehicles)&&!value.vehicles.some(vehicle=>vehicle.id===2));
  evidence.layouts.push({label:'dispatch-observed',...layout});persist();
 });
 await page.waitForTimeout(2200);
 await screenshot('02-truck-touch-and-road');
 await check('real truck touch persists a non-yard stage1 truck',async()=>{
  const saved=await pollSave(page,activeStageOne,'Touch must dispatch an actual truck');recordSave('save-after-touch',saved);
 });
 if(!layoutOnly||option('--rotate-to',''))await check('real two-finger pinch and one-finger pan update camera without truck dispatch',()=>testGestures(!layoutOnly));
 phase='pause-settings';
 await touchControl('pause','pause');
 await screenshot('03-paused');
 await environment('pause-before-effects');
 await auditLayout('layout-pause');
 if(layoutOnly) {
  const resizeHeights=option('--resize-heights','').split(',').filter(Boolean).map(Number);
  for(const newHeight of resizeHeights) {
   assert.ok(newHeight>0,'Positive dynamic height');
   await page.setViewportSize({width,height:newHeight});
   await renderedFrames();
   await auditLayout('layout-height-'+newHeight,{width,height:newHeight});
  }
  if(resizeHeights.length) {
   await touchControl('modal_continue','resume-after-height-resize');
   await renderedFrames();
   await auditLayout('layout-after-height-resume');
   await pollSave(page,activeStageOne,'Height resizing retains actual dispatched truck');
  }
  const rotate=option('--rotate-to','');
  if(rotate) {
   const [newWidth,newHeight]=rotate.split('x').map(Number);
   assert.ok(newWidth>0&&newHeight>0,'Valid rotation dimensions');
   await page.setViewportSize({width:newWidth,height:newHeight});
   await renderedFrames();
   await auditLayout('layout-rotated-pause',{width:newWidth,height:newHeight});
   await touchControl('modal_continue','resume-after-rotation');
   await renderedFrames();
   await auditLayout('layout-rotated-stage',{width:newWidth,height:newHeight});
   await pollSave(page,activeStageOne,'Rotation retains real dispatched campaign truck');
  }
 } else {
 const beforeMute=await pollSave(page,activeStageOne,'Pause must retain active campaign');
 assert.equal(setting(beforeMute.text,'sound'),true,'Fresh isolated profile starts with effects enabled');
 assert.equal(setting(beforeMute.text,'music'),true,'Fresh isolated profile starts with music enabled');
 await touchControl('effects','effects-off'); // Real effects button; never blindly retry a toggle.
 await screenshot('04a-immediately-after-effects-touch');
 await environment('after-effects-touch');
 await check('effects button persists sound=false before next touch',async()=>{
  const saved=await pollSave(page,text=>activeStageOne(text)&&setting(text,'sound')===false,'Effects touch must persist sound=false');recordSave('save-effects-off',saved);
 });
 await touchControl('music','music-off'); // Only after the previous mutation is observed.
 await screenshot('04b-immediately-after-music-touch');

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
 await touchControl('harbor_play','resume-stage1'); // Actual current Fortsätt primary action.
 await page.waitForTimeout(800);
 await screenshot('06-resumed-stage');
 await touchControl('pause','pause-after-reload');
 await screenshot('07-resumed-pause');
 await auditLayout('layout-reloaded-pause');
 }
 const fatalConsole=evidence.console.filter(message=>message.type==='error'||/SCRIPT ERROR|Missing local audio|ERROR:|ResourceLoader.*(?:error|failed)/i.test(message.text));
 const badResponses=evidence.responses.filter(response=>response.status>=400);
 evidence.fatalConsole=fatalConsole;evidence.badResponses=badResponses;
 assert.deepEqual(evidence.pageErrors,[],'No browser runtime exceptions');
 assert.deepEqual(evidence.requestFailures,[],'No failed network requests');
 assert.deepEqual(badResponses,[],'No HTTP4xx/5xx asset responses');
 assert.deepEqual(fatalConsole,[],'No Godot/script/audio/resource errors');
 evidence.ok=true;persist();
 console.log(layoutOnly?'WEB_MOBILE_LAYOUT_OK: responsive controls44CSSpx, no letterbox, actual truck touch, observed cargo geometry':'WEB_BROWSER_SMOKE_OK: responsive real mobile touch, pause mute, IndexedDB save/reload, no runtime/resource/network errors');
})().catch(async error=>{
 evidence.ok=false;evidence.failure=String(error.stack||error);persist();console.error(error);process.exitCode=1;
 if(page && !page.isClosed()) {
  try {await page.screenshot({scale:'css',path:path.join(output,'failure-screen.png')});}
  catch(diagnosticError){evidence.failureScreenshotError=String(diagnosticError);}
  try {const saved=await readSave(page);if(saved)recordSave('failure-last',saved);}
  catch(diagnosticError){evidence.failureSaveError=String(diagnosticError);}
 }
 persist();
}).finally(async()=>{if(browser)await browser.close();persist();});

// Decode Chromium screenshot PNG edges using built-in zlib, no image dependency.
// A canvas can cover CSS space while Godot still draws internal black bars.
function decodeScreenshot(png) {
 let offset=8,width,height,channels;const data=[];
 while(offset<png.length) {
  const length=png.readUInt32BE(offset),type=png.toString('ascii',offset+4,offset+8),chunk=png.subarray(offset+8,offset+8+length);
  if(type==='IHDR') {width=chunk.readUInt32BE(0);height=chunk.readUInt32BE(4);assert.equal(chunk[8],8,'8-bit screenshot PNG');channels=chunk[9]===6?4:chunk[9]===2?3:0;assert.ok(channels,'RGB/RGBA screenshot PNG');}
  if(type==='IDAT')data.push(chunk);
  offset+=length+12;
 }
 const raw=zlib.inflateSync(Buffer.concat(data)),stride=width*channels,pixels=Buffer.alloc(stride*height);
 const paeth=(a,b,c)=>{const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);return pa<=pb&&pa<=pc?a:pb<=pc?b:c;};
 for(let y=0;y<height;y++) {
  const filter=raw[y*(stride+1)],start=y*(stride+1)+1;
  for(let x=0;x<stride;x++) {const a=x>=channels?pixels[y*stride+x-channels]:0,b=y?pixels[(y-1)*stride+x]:0,c=y&&x>=channels?pixels[(y-1)*stride+x-channels]:0;let value=raw[start+x];if(filter===1)value+=a;else if(filter===2)value+=b;else if(filter===3)value+=Math.floor((a+b)/2);else if(filter===4)value+=paeth(a,b,c);else assert.equal(filter,0,'Known PNG filter');pixels[y*stride+x]=value&255;}
 }
 return {width,height,pixels,stride,channels};
}
function blackEdgeBands(png) {
 const {width,height,pixels,stride,channels}=decodeScreenshot(png);
 const black=(x,y)=>{const i=y*stride+x*channels;return pixels[i]<5&&pixels[i+1]<5&&pixels[i+2]<5;};
 const row=y=>{let n=0;for(let x=0;x<width;x++)if(black(x,y))n++;return n/width>.985;};
 const column=x=>{let n=0;for(let y=0;y<height;y++)if(black(x,y))n++;return n/height>.985;};
 const result={top:0,bottom:0,left:0,right:0};
 while(result.top<height&&row(result.top))result.top++;
 while(result.bottom<height&&row(height-1-result.bottom))result.bottom++;
 while(result.left<width&&column(result.left))result.left++;
 while(result.right<width&&column(width-1-result.right))result.right++;
 return result;
}

function regionPixels(png,rect,exclude) {
 const {width,height,pixels,stride,channels}=decodeScreenshot(png);
 const colors=new Map();let samples=0;
 const left=Math.max(0,Math.ceil(rect.x+4)),right=Math.min(width,Math.floor(rect.x+rect.width-4));
 const top=Math.max(0,Math.ceil(rect.y+4)),bottom=Math.min(height,Math.floor(rect.y+rect.height-4));
 for(let y=top;y<bottom;y++)for(let x=left;x<right;x++) {
  // Exclude the real overlay card plus its shadow, not UI pixels pretending
  // to prove that an underlying frozen3D texture was refreshed on resize.
  if(exclude&&x>=exclude.x-8&&x<=exclude.x+exclude.width+8&&y>=exclude.y-8&&y<=exclude.y+exclude.height+8)continue;
  const i=y*stride+x*channels;
  const key=(pixels[i]>>3)*1024+(pixels[i+1]>>3)*32+(pixels[i+2]>>3);
  colors.set(key,(colors.get(key)||0)+1);samples++;
 }
 return {samples,colorBins:colors.size,dominantFraction:samples?Math.max(...colors.values())/samples:1};
}
