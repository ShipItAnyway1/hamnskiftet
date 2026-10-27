#!/usr/bin/env node
'use strict';
// Short real-touch layout matrix. The full390×844 mute/reload regression remains
// in browser_smoke.cjs; every case here launches a clean browser context.
const fs=require('node:fs');
const path=require('node:path');
const {spawn}=require('node:child_process');
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
(async()=>{
 for(const item of cases)await run(item);
 report.ok=report.cases.every(item=>item.ok);persist();
 if(!report.ok){process.exitCode=1;console.error('WEB_MOBILE_MATRIX_FAILED: '+report.cases.filter(item=>!item.ok).map(item=>item.name).join(', '));}
 else console.log('WEB_MOBILE_MATRIX_OK: '+report.cases.length+' viewport/safe-area/rotation cases, real touch,44CSSpx UI and no internal letterbox');
})().catch(error=>{report.failure=String(error.stack||error);persist();console.error(error);process.exitCode=1;});
