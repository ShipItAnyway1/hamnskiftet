#!/usr/bin/env node
'use strict';
// Short real-touch layout matrix. The full390×844 mute/reload regression remains
// in browser_smoke.cjs; every case here launches a clean browser context.
const fs=require('node:fs');
const path=require('node:path');
const {spawn}=require('node:child_process');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
function option(name,fallback){const at=process.argv.indexOf(name);return at<0?fallback:process.argv[at+1];}
const url=option('--url',process.env.BASE_URL||'http://127.0.0.1:8765/');
const output=path.resolve(option('--output-dir','ci-results/mobile-layout'));
const selected=option('--cases','').split(',').filter(Boolean);
const cases=[
 {name:'phone-360x640',width:360,height:640},
 {name:'phone-390x844',width:390,height:844,resizeHeights:'680,844'},
 {name:'phone-430x932-retina',width:430,height:932,dpr:3},
 {name:'tablet-768x1024',width:768,height:1024},
 {name:'landscape-and-rotation',width:844,height:390,rotate:'390x844'},
 {name:'safe-area-390x844',width:390,height:844,top:24,bottom:20}
].filter(item=>!selected.length||selected.includes(item.name));
if(!cases.length)throw new Error('No matching --cases names');
fs.mkdirSync(output,{recursive:true});
const report={url,kind:'real-Chromium-mobile-emulation',deviceTest:false,cases:[],ok:false};
const persist=()=>fs.writeFileSync(path.join(output,'matrix.json'),JSON.stringify(report,null,2));
function run(item){return new Promise(resolve=>{
 const destination=path.join(output,item.name);
 const args=[path.join(__dirname,'browser_smoke.cjs'),'--url',url,'--output-dir',destination,'--layout-only','--width',String(item.width),'--height',String(item.height)];
 if(item.rotate)args.push('--rotate-to',item.rotate);
 if(item.dpr)args.push('--dpr',String(item.dpr));
 if(item.resizeHeights)args.push('--resize-heights',item.resizeHeights);
 if(item.top)args.push('--safe-top',String(item.top));
 if(item.bottom)args.push('--safe-bottom',String(item.bottom));
 const started=Date.now();
 const child=spawn(process.execPath,args,{env:process.env,stdio:['ignore','pipe','pipe']});
 let log='';
 const record=chunk=>{const text=String(chunk);log+=text;process.stdout.write('['+item.name+'] '+text);};
 child.stdout.on('data',record);child.stderr.on('data',record);
 const timeout=setTimeout(()=>{record('Layout case exceeded5minutes; terminating browser test\n');child.kill('SIGTERM');},300000);
 child.on('error',error=>record(String(error)));
 child.on('close',(code,signal)=>{
  clearTimeout(timeout);
  fs.mkdirSync(destination,{recursive:true});fs.writeFileSync(path.join(destination,'runner.log'),log);
  let evidence;
  try{evidence=JSON.parse(fs.readFileSync(path.join(destination,'evidence.json'),'utf8'));}catch{}
  const result={...item,exitCode:code,signal,elapsedMs:Date.now()-started,ok:code===0&&evidence?.ok===true,audits:evidence?.layoutAudits||[],failure:evidence?.failure};
  report.cases.push(result);persist();resolve(result);
 });
});}

// A fresh menu-only context proves real finger scrolling over a card body.
// All game state/layout reads are observational; never set a scroll property.
async function testHarborFingerScroll(item) {
 const directory=path.join(output,item.name,'harbor-finger-scroll');
 fs.mkdirSync(directory,{recursive:true});
 const evidence={url,viewport:{width:item.width,height:item.height},deviceTest:false,layouts:[],gestures:[],inputEvents:[],errors:[],badResponses:[],requestFailures:[]};
 const save=()=>fs.writeFileSync(path.join(directory,'evidence.json'),JSON.stringify(evidence,null,2));
 let browser,page;
 try {
  const launch={headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--enable-webgl','--disable-dev-shm-usage']};
  if(process.env.PLAYWRIGHT_EXECUTABLE_PATH)launch.executablePath=process.env.PLAYWRIGHT_EXECUTABLE_PATH;
  browser=await chromium.launch(launch);
  const context=await browser.newContext({viewport:evidence.viewport,hasTouch:true,isMobile:true,deviceScaleFactor:1});
  await context.addInitScript(()=>{
   for(const type of ['touchstart','touchmove','touchend','touchcancel'])document.addEventListener(type,event=>{
    console.debug('__HARBOR_SCROLL__'+JSON.stringify({type,isTrusted:event.isTrusted,at:Date.now(),points:Array.from(event.changedTouches).map(touch=>({x:touch.clientX,y:touch.clientY}))}));
   },{capture:true,passive:true});
  });
  page=await context.newPage();page.setDefaultTimeout(120000);
  page.on('console',message=>{
   const text=message.text();
   if(text.startsWith('__HARBOR_SCROLL__'))evidence.inputEvents.push(JSON.parse(text.slice('__HARBOR_SCROLL__'.length)));
   else if(message.type()==='error'||/SCRIPT ERROR|Missing local audio|ERROR:|ResourceLoader.*(?:error|failed)/i.test(text))evidence.errors.push(text);
   save();
  });
  page.on('pageerror',error=>{evidence.errors.push(String(error));save();});
  page.on('response',response=>{if(response.status()>=400){evidence.badResponses.push({url:response.url(),status:response.status()});save();}});
  page.on('requestfailed',request=>{evidence.requestFailures.push({url:request.url(),error:request.failure()});save();});
  const cdp=await context.newCDPSession(page);
  const layout=async predicate=>{
   const deadline=Date.now()+120000;
   while(Date.now()<deadline){
    const data=await page.evaluate(()=>{try{return JSON.parse(document.getElementById('game-layout')?.textContent||'null');}catch{return null;}});
    if(data?.version===1&&data.screen==='harbor'&&(!predicate||predicate(data)))return data;
    await page.waitForTimeout(100);
   }
   throw new Error('Actual harbor scroll layout did not satisfy expected geometry');
  };
  const config=()=>page.evaluate(async()=>{
   const result=[];
   for(const info of await indexedDB.databases()){
    const db=await new Promise((resolve,reject)=>{const q=indexedDB.open(info.name);q.onsuccess=()=>resolve(q.result);q.onerror=()=>reject(q.error);});
    try{
     if(!db.objectStoreNames.contains('FILE_DATA'))continue;
     const records=await new Promise((resolve,reject)=>{
      const store=db.transaction('FILE_DATA','readonly').objectStore('FILE_DATA');
      const keys=store.getAllKeys();keys.onerror=()=>reject(keys.error);keys.onsuccess=()=>{
       Promise.all(keys.result.filter(key=>String(key).endsWith('/hamnskiftet.cfg')).map(key=>new Promise((done,fail)=>{
        const q=store.get(key);q.onerror=()=>fail(q.error);q.onsuccess=()=>done({key:String(key),text:new TextDecoder().decode(new Uint8Array(q.result.contents))});
       }))).then(resolve,reject);
      };
     });
     result.push(...records);
    }finally{db.close();}
   }
   return result;
  });
  const cssRect=async(rect,data)=>{
   const canvas=await page.locator('#canvas').boundingBox();
   return{x:canvas.x+rect[0]*canvas.width/data.viewport.w,y:canvas.y+rect[1]*canvas.height/data.viewport.h,width:rect[2]*canvas.width/data.viewport.w,height:rect[3]*canvas.height/data.viewport.h};
  };
  await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});await page.locator('#play').tap();
  await page.waitForFunction(()=>document.documentElement.dataset.gameReady==='true');
  let data=await layout(value=>Object.values(value.controls).some(control=>control.text==='Lastbilar'&&control.visible&&!control.clipped));
  const tab=Object.values(data.controls).find(control=>control.text==='Lastbilar'&&control.visible&&!control.clipped);
  const tabRect=await cssRect(tab.rect,data);
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:tabRect.x+tabRect.width*.5,y:tabRect.y+tabRect.height*.5,id:1}]});
  await page.waitForTimeout(100);await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  data=await layout(value=>Object.entries(value.controls).filter(([key,control])=>key.includes('/UpgradeScroll/')&&control.text==='Låst'&&control.visible).length===2);
  const lockedKeys=Object.entries(data.controls).filter(([key,control])=>key.includes('/UpgradeScroll/')&&control.text==='Låst'&&control.visible).map(([key])=>key);
  const rightButtons=Object.entries(data.controls).filter(([key,control])=>key.includes('/UpgradeScroll/')&&control.visible&&control.rect[0]>data.viewport.w*.5).sort((a,b)=>a[1].rect[1]-b[1].rect[1]);
  assert.ok(rightButtons.length>=3,'Three actual right-column fleet buttons establish card-body geometry');
  assert.ok(lockedKeys.some(key=>data.controls[key].clipped),'Last ADR/fuel controls initially need a finger scroll');
  const before=data,playBefore=await cssRect(data.controls.harbor_play.rect,data),saveBefore=await config();
  evidence.layouts.push({label:'before-card-swipe',...data});
  await page.screenshot({scale:'css',path:path.join(directory,'01-before-card-swipe.png')});
  // Both points are80logical pixels ABOVE a real button, inside the right
  // card body. This deliberately avoids the narrow gap that hid the defect.
  const bodyPoint=async button=>{
   const rect=await cssRect([button.rect[0]+button.rect[2]*.5,button.rect[1]-80,0,0],before);
   return{x:rect.x,y:rect.y};
  };
  const start=await bodyPoint(rightButtons[1][1]),end=await bodyPoint(rightButtons[0][1]);
  assert.ok(start.y>end.y+80,'Finger swipe crosses enough actual card body');
  for(const control of Object.values(before.controls).filter(control=>control.visible)){
   const rect=await cssRect(control.rect,before);
   assert.ok(!(start.x>=rect.x&&start.x<=rect.x+rect.width&&start.y>=rect.y&&start.y<=rect.y+rect.height),'Swipe starts outside every real Button, including disabled purchase buttons');
  }
  evidence.gestures.push({start,end,steps:14,method:'CDP real touchMove across right fleet card body'});save();
  try{
   await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{...start,id:1}]});
   for(let step=1;step<=14;step++){
    await page.waitForTimeout(45);const fraction=step/14;
    await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:start.x+(end.x-start.x)*fraction,y:start.y+(end.y-start.y)*fraction,id:1}]});
   }
  }finally{await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});}
  data=await layout(value=>lockedKeys.every(key=>value.controls[key]?.visible&&!value.controls[key].clipped));
  evidence.layouts.push({label:'after-card-swipe',...data});
  await page.screenshot({scale:'css',path:path.join(directory,'02-after-card-swipe.png')});
  assert.ok(data.controls[lockedKeys[0]].rect[1]<before.controls[lockedKeys[0]].rect[1]-20,'Actual card button geometry moved upwards');
  assert.deepEqual(await cssRect(data.controls.harbor_play.rect,data),playBefore,'Sticky Spela stays fixed during real finger scrolling');
  assert.ok(data.controls.harbor_play.visible&&!data.controls.harbor_play.clipped&&!data.controls.harbor_play.disabled,'Spela remains fully reachable');
  assert.ok(evidence.inputEvents.some(event=>event.type==='touchmove'&&event.isTrusted),'Native trusted touchMove reached the canvas');
  assert.deepEqual(await config(),saveBefore,'Finger scroll does not buy upgrades or create a campaign save');
  assert.equal(data.screen,'harbor','Finger scroll does not start a stage');
  assert.deepEqual(evidence.errors,[],'No game/browser runtime errors');assert.deepEqual(evidence.badResponses,[],'No failing assets');assert.deepEqual(evidence.requestFailures,[],'No failed network requests');
  evidence.ok=true;save();console.log('PASS real360px card-body finger swipe: last ADR/fuel buttons visible, sticky Play fixed, no purchase/stage start');
 }catch(error){
  evidence.ok=false;evidence.failure=String(error.stack||error);save();
  if(page)await page.screenshot({scale:'css',path:path.join(directory,'failure.png')}).catch(()=>{});
  console.error('FAIL real harbor finger scroll: '+evidence.failure);
 }finally{if(browser)await browser.close();save();}
 return{ok:evidence.ok===true,evidence:path.relative(output,path.join(directory,'evidence.json')),failure:evidence.failure};
}

(async()=>{
 for(const item of cases){
  const result=await run(item);
  if(item.name==='phone-360x640'&&result.ok){
   result.harborFingerScroll=await testHarborFingerScroll(item);
   result.ok=result.ok&&result.harborFingerScroll.ok;persist();
  }
 }
 report.ok=report.cases.every(item=>item.ok);persist();
 if(!report.ok){process.exitCode=1;console.error('WEB_MOBILE_MATRIX_FAILED: '+report.cases.filter(item=>!item.ok).map(item=>item.name).join(', '));}
 else console.log('WEB_MOBILE_MATRIX_OK: '+report.cases.length+' viewport/safe-area/rotation cases, real touch,44CSSpx UI and no internal letterbox');
})().catch(error=>{report.failure=String(error.stack||error);persist();console.error(error);process.exitCode=1;});
