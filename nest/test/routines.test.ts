import { readFileSync } from 'node:fs';
import { routineSchema } from '../src/contracts.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { Temporal } from '@js-temporal/polyfill';
import { testDatabase } from './database.js';
import { Repository } from '../src/storage/repository.js';
import { NestService } from '../src/domain.js';
const now='2026-10-01T01:00:00Z';
const day={year:2030,month:10,day:1};
const mutation=(kind:string,entityID:string,payload:unknown,expectedRevision=0)=>({operationID:crypto.randomUUID(),kind,entityID,payload,expectedRevision,deleted:false});
async function setup(){const db=await testDatabase();const repo=new Repository(db),service=new NestService(repo);const user=await repo.identify('test','alice','Asia/Shanghai');return {db,repo,service,user};}
function routine(){return {id:crypto.randomUUID(),title:'Workday',createdAt:now,updatedAt:now,blocks:[{id:crypto.randomUUID(),layerIndex:0,title:'Morning',reminders:[],taskBlueprints:[{id:crypto.randomUUID(),title:'Water',order:0}],timing:{absolute:{startMinuteOfDay:540,requestedEndMinuteOfDay:600}}}]};}
test('routine default effective date is tomorrow in account time zone',async()=>{
 const {db,repo,service,user}=await setup();const payload=routine();await service.push(user,mutation('routine',payload.id,payload));
 const saved=(await repo.get(user,'routine',payload.id))!.body as any;const expected=Temporal.Now.zonedDateTimeISO(user.timeZoneID).toPlainDate().add({days:1});assert.deepEqual(saved.effectiveFrom,{year:expected.year,month:expected.month,day:expected.day});db.db.close();
});
test('execution is an idempotent desired state and freezes its source snapshot',async()=>{
 const {db,repo,service,user}=await setup();const payload={...routine(),effectiveFrom:day};await service.push(user,mutation('routine',payload.id,payload));
 await service.push(user,mutation('dateException','2030-10-01',{date:day,savedTemplateID:payload.id}));const plan=(await service.materialize(user,day))!;
 const block=plan.blocks[0],task=block.tasks[0];assert.notEqual(block.id,payload.blocks[0].id);assert.equal(block.sourceBlockID,payload.blocks[0].id);
 const op=mutation('execution',task.id,{planID:plan.id,planRevision:plan.revision,blockInstanceID:block.id,taskInstanceID:task.id,isCompleted:true,occurredAt:now,timeZoneID:user.timeZoneID,source:'ios'});
 await service.push(user,op);await service.push(user,op);
 await service.push(user,{...op,operationID:crypto.randomUUID(),expectedRevision:1,payload:{...op.payload as object,isCompleted:false}});
 await service.push(user,mutation('routine',payload.id,{...payload,title:'New title'},1));
 assert.equal((await service.materialize(user,day))?.revision,1);assert.equal((await repo.get(user,'execution',task.id))?.revision,2);
 const events=(await service.timeline(user,'2026-10-01T00:00:00Z','2026-10-02T00:00:00Z')).items.filter(x=>x.kind==='execution');assert.equal(events.length,2);assert.equal(new Set(events.map(x=>x.id)).size,2);
 assert.equal((await db.all('SELECT * FROM operations WHERE kind=?',['execution'])).length,2);db.db.close();
});
test('an empty day has no routine and can still contain a standalone note',async()=>{
 const {db,service,user}=await setup();assert.equal(await service.materialize(user,day),undefined);
 const id=crypto.randomUUID();await service.push(user,mutation('note',id,{id,text:'No routine needed',occurredAt:now,timeZoneID:user.timeZoneID,createdAt:now,updatedAt:now,source:'agent'}));
 assert.equal((await service.timeline(user,'2026-10-01T00:00:00Z','2026-10-02T00:00:00Z')).items.length,1);db.db.close();
});
test('concurrent materialization creates one stable day plan',async()=>{
 const {db,repo,service,user}=await setup();const payload={...routine(),effectiveFrom:day};await service.push(user,mutation('routine',payload.id,payload));
 await service.push(user,mutation('dateException','2030-10-01',{date:day,savedTemplateID:payload.id}));
 const [a,b]=await Promise.all([service.materialize(user,day),service.materialize(user,day)]);assert.equal(a?.id,b?.id);assert.equal((await repo.list(user,'plan')).length,1);db.db.close();
});
test('timezone setup requires confirmation and changes enter sync without altering history',async()=>{
 const {db,repo,service}=await setup();const user=await repo.identify('test','new-user');const r=routine();
 await assert.rejects(service.push(user,mutation('routine',r.id,r)),(e:any)=>e.code==='time_zone_setup_required');
 await assert.rejects(service.setTimeZone(user,'Asia/Shanghai','UTC',false));
 const boot=await repo.bootstrap(user);const updated=await service.setTimeZone(user,'Asia/Shanghai','UTC',true);
 assert.equal(updated.timeZoneConfirmed,true);assert.equal((await repo.identify('test','new-user')).timeZoneID,'Asia/Shanghai');
 const page=await repo.pull(user,boot.cursor);assert.equal(page.changes[0].kind,'account');db.db.close();
});
test('clearing a future selection propagates an empty plan while preserving its prior version',async()=>{
 const {db,repo,service,user}=await setup();try{
  const value={...routine(),effectiveFrom:day};await service.push(user,mutation('routine',value.id,value));
  await service.push(user,mutation('dateException','2030-10-01',{date:day,savedTemplateID:value.id}));
  const plan=(await service.materialize(user,day))!;
  await service.push(user,mutation('dateException','2030-10-01',{date:day,savedTemplateID:null},1));
  const cleared=(await service.materialize(user,day))!;assert.equal(cleared.blocks.length,0);assert.equal(cleared.id,plan.id);assert.equal(cleared.revision,2);
  assert.equal((await repo.db.all('SELECT * FROM operations WHERE kind=?',['plan'])).length,2);
 }finally{db.db.close();}
});
test('imported legacy checklist accepts new execution without guessing template links',async()=>{
 const {db,service,user}=await setup();try{
  const id=crypto.randomUUID(),blockID=crypto.randomUUID(),taskID=crypto.randomUUID();
  const plan={id,date:{year:2020,month:1,day:1},source:'legacy',hasUserEdits:true,blocks:[{id:blockID,dayPlanID:id,layerIndex:0,kind:'userDefined',title:'Imported',reminders:[],tasks:[{id:taskID,title:'Original',order:0,isCompleted:false}],timing:{absolute:{startMinuteOfDay:60,requestedEndMinuteOfDay:120}},resolvedStartMinuteOfDay:60,resolvedEndMinuteOfDay:120,isCancelled:false}]};
  await service.push(user,mutation('legacyPlan',id,plan));
  await service.push(user,mutation('execution',taskID,{planID:id,planRevision:1,blockInstanceID:blockID,taskInstanceID:taskID,isCompleted:true,occurredAt:now,timeZoneID:user.timeZoneID,source:'ios'}));
 }finally{db.db.close();}
});

test('legacy history respects the exclusive midnight end of a timeline query',async()=>{
 const {db,service,user}=await setup();try{
  for(const d of [1,2]){const id=crypto.randomUUID();await service.push(user,mutation('legacyPlan',id,{id,date:{year:2020,month:1,day:d},source:'legacy',hasUserEdits:false,blocks:[]}));}
  const page=await service.timeline(user,'2020-01-01T00:00:00+08:00','2020-01-02T00:00:00+08:00');assert.equal(page.legacyPlans.length,1);
 }finally{db.db.close();}
});
test('successive cached-base corrections keep task edits and their offline execution source',async()=>{
 const {db,repo,service,user}=await setup();try{
  const value={...routine(),effectiveFrom:day};await service.push(user,mutation('routine',value.id,value));
  await service.push(user,mutation('dateException','2030-10-01',{date:day,savedTemplateID:value.id}));
  const plan=(await service.materialize(user,day))!,block=plan.blocks[0],taskID=crypto.randomUUID();
  const correction=mutation('dayCorrection',block.id,{date:day,planID:plan.id,planRevision:plan.revision,blockInstanceID:block.id,startMinuteOfDay:540,endMinuteOfDay:590,title:'Adjusted',tasks:[...block.tasks.map(({id,sourceTaskID,title,order})=>({id,sourceTaskID,title,order})),{id:taskID,title:'Added offline',order:1}]});
  await service.push(user,correction);
  const second={...correction,operationID:crypto.randomUUID(),expectedRevision:1,payload:{...correction.payload as object,endMinuteOfDay:580}};
  await service.push(user,second);
  const current=(await service.materialize(user,day))!;assert.equal(current.blocks[0].resolvedEndMinuteOfDay,580);assert.equal(current.blocks[0].tasks[1].id,taskID);
  const execution=mutation('execution',taskID,{planID:plan.id,planRevision:plan.revision,blockInstanceID:block.id,taskInstanceID:taskID,isCompleted:true,occurredAt:now,timeZoneID:user.timeZoneID,source:'ios',correctionOperationID:second.operationID});
  await service.push(user,execution);assert.equal((await repo.get(user,'execution',taskID))?.revision,1);
  await assert.rejects(service.push(user,{...execution,operationID:crypto.randomUUID(),expectedRevision:1,payload:{...execution.payload as object,correctionOperationID:crypto.randomUUID()}}),(e:any)=>e.code==='unknown_correction');
 }finally{db.db.close();}
});

test('offline snapshots validate cached versions and keep executed source after cloud changes',async()=>{
 const {db,repo,service,user}=await setup();try{
  const value={...routine(),effectiveFrom:day};await service.push(user,mutation('routine',value.id,value));
  await service.push(user,mutation('dateException','2030-10-01',{date:day,savedTemplateID:value.id}));
  const cache=await repo.scheduleCache(user),id=crypto.randomUUID(),blockID=crypto.randomUUID(),taskID=crypto.randomUUID();
  const input={id,date:day,sourceSavedTemplateID:value.id,sourceRevision:1,sourceCursor:cache.cursor,timeZoneID:cache.timeZoneID,blocks:[{id:blockID,sourceBlockID:value.blocks[0].id,tasks:[{id:taskID,sourceTaskID:value.blocks[0].taskBlueprints[0].id}]}]};
  await service.push(user,mutation('routine',value.id,{...value,blocks:[{...value.blocks[0],title:'Changed while offline'}]},1));
  const cloud=(await service.materialize(user,day))!;
  const operation=mutation('offlinePlan',id,input),accepted=await service.push(user,operation);
  assert.equal((accepted.body as any).blocks[0].title,'Morning');assert.equal((accepted.body as any).sourceRevision,1);assert.notEqual(cloud.id,id);
  assert.deepEqual(await service.push(user,operation),accepted);
  await service.push(user,mutation('execution',taskID,{planID:id,planRevision:1,blockInstanceID:blockID,taskInstanceID:taskID,isCompleted:true,occurredAt:'2030-10-01T01:30:00Z',timeZoneID:user.timeZoneID,source:'ios'}));
  const timeline=await service.timeline(user,'2030-10-01T00:00:00+08:00','2030-10-02T00:00:00+08:00');
  assert.ok(timeline.items.some(x=>x.kind==='offlinePlan'&&x.id===id));
  assert.equal((await repo.get(user,'plan',cloud.id))?.revision,1);
  const bob=await repo.identify('test','bob','Asia/Shanghai');await assert.rejects(service.push(bob,operation),(e:any)=>e.code==='invalid_cursor');
  const wrongID=crypto.randomUUID();await assert.rejects(service.push(user,mutation('offlinePlan',wrongID,{...input,id:wrongID,sourceRevision:2})),(e:any)=>e.code==='offline_source_mismatch');
 }finally{db.db.close();}
});

test('Swift routine wire fixture passes the strict contract and sync service',async()=>{
 const payload=JSON.parse(readFileSync(new URL('../contracts/ios-routine.json',import.meta.url),'utf8'));
 assert.equal(routineSchema.safeParse(payload).success,true);
 assert.equal(routineSchema.safeParse({...payload,versionID:crypto.randomUUID()}).success,false);
 const {db,repo,service,user}=await setup();
 await service.push(user,mutation('routine',payload.id,payload));
 assert.equal(((await repo.get(user,'routine',payload.id))!.body as any).title,payload.title);
 db.db.close();
});
