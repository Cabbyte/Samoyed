import test from 'node:test';
import assert from 'node:assert/strict';
import { testDatabase } from './database.js';
import { Repository } from '../src/storage/repository.js';
import { NestService, validatePlanStructure, type Plan } from '../src/domain.js';

const day={year:2030,month:10,day:1};
const now='2026-10-01T01:00:00Z';
const wire=<T>(value:T):T=>JSON.parse(JSON.stringify(value));
const command=(kind:string,entityID:string,payload:unknown,expectedRevision=0)=>({operationID:crypto.randomUUID(),kind,entityID,payload,expectedRevision,deleted:false});
function block(title:string,start:number,end:number){return {id:crypto.randomUUID(),layerIndex:0,title,reminders:[],taskBlueprints:[{id:crypto.randomUUID(),title:'Task',order:0}],timing:{absolute:{startMinuteOfDay:start,requestedEndMinuteOfDay:end}}};}
function routine(blocks:any[]){return {id:crypto.randomUUID(),title:'Routine',createdAt:now,updatedAt:now,effectiveFrom:day,blocks};}
async function setup(){const db=await testDatabase(),repo=new Repository(db),service=new NestService(repo),user=await repo.identify('test','recovery','Asia/Shanghai');return {db,repo,service,user};}
async function select(context:Awaited<ReturnType<typeof setup>>,value:ReturnType<typeof routine>,revision=0){
 await context.service.push(context.user,command('routine',value.id,value));
 await context.service.push(context.user,command('dateException','2030-10-01',{date:day,savedTemplateID:value.id},revision));
}
async function execute(context:Awaited<ReturnType<typeof setup>>,plan:Plan,target:Plan['blocks'][number]){
 return context.service.push(context.user,command('execution',target.tasks[0].id,{planID:plan.id,planRevision:plan.revision,blockInstanceID:target.id,taskInstanceID:target.tasks[0].id,isCompleted:true,occurredAt:now,timeZoneID:plan.timeZoneID,source:'ios'}));
}
function nestedRoutine(){
 const root=block('Deep work',540,690);
 const child={...block('Child',575,645),parentTemplateBlockID:root.id,layerIndex:1,timing:{relative:{startOffsetMinutes:35,requestedDurationMinutes:70}}};
 return routine([root,child]);
}

test('overlapping replacement keeps the complete valid executed snapshot and its source',async()=>{
 const c=await setup();try{
  const original=routine([block('Housework',570,660)]);await select(c,original);
  const before=(await c.service.materialize(c.user,day))!;await execute(c,before,before.blocks[0]);
  await select(c,nestedRoutine(),1);
  const after=(await c.service.materialize(c.user,day))!;
  assert.deepEqual(wire(after),wire(before));validatePlanStructure(after);
  assert.equal((await c.repo.list(c.user,'plan'))[0].revision,1);
 }finally{c.db.db.close();}
});

test('executing a child retains its full parent subtree when the rest of the day changes',async()=>{
 const c=await setup();try{
  const original=nestedRoutine();await select(c,original);
  const before=(await c.service.materialize(c.user,day))!;await execute(c,before,before.blocks[1]);
  const replacement=routine([block('Afternoon',780,840)]);await select(c,replacement,1);
  const after=(await c.service.materialize(c.user,day))!;validatePlanStructure(after);
  assert.deepEqual(wire(after.blocks.slice(0,2)),wire(before.blocks));
  assert.equal(after.blocks[2].title,'Afternoon');
  await c.service.push(c.user,command('dateException','2030-10-01',{date:day,savedTemplateID:null},2));
  const cleared=(await c.service.materialize(c.user,day))!;validatePlanStructure(cleared);
  assert.deepEqual(wire(cleared.blocks),wire(before.blocks));
 }finally{c.db.db.close();}
});

test('same-routine updates keep new children out of an already executed subtree',async()=>{
 const c=await setup();try{
  const original=nestedRoutine();await select(c,original);
  const before=(await c.service.materialize(c.user,day))!;await execute(c,before,before.blocks[0]);
  const extra={...block('New child',645,660),parentTemplateBlockID:original.blocks[0].id,layerIndex:1};
  await c.service.push(c.user,command('routine',original.id,{...original,blocks:[...original.blocks,extra]},1));
  const after=(await c.service.materialize(c.user,day))!;validatePlanStructure(after);
  assert.deepEqual(wire(after),wire(before));
 }finally{c.db.db.close();}
});

test('unexecuted future plans can still switch routines completely',async()=>{
 const c=await setup();try{
  await select(c,routine([block('Housework',570,660)]));await c.service.materialize(c.user,day);
  const replacement=nestedRoutine();await select(c,replacement,1);
  const after=(await c.service.materialize(c.user,day))!;validatePlanStructure(after);
  assert.equal(after.sourceSavedTemplateID,replacement.id);
  assert.equal(after.blocks.length,2);assert.equal(after.revision,2);
 }finally{c.db.db.close();}
});

test('correcting a parent start preserves the validated absolute times of its children',async()=>{
 const c=await setup();try{
  await select(c,nestedRoutine());
  const before=(await c.service.materialize(c.user,day))!;
  await c.service.push(c.user,command('dayCorrection',before.blocks[0].id,{date:day,planID:before.id,planRevision:before.revision,blockInstanceID:before.blocks[0].id,startMinuteOfDay:510,endMinuteOfDay:690}));
  const after=(await c.service.materialize(c.user,day))!;validatePlanStructure(after);
  assert.equal(after.blocks[0].resolvedStartMinuteOfDay,510);
  assert.equal(after.blocks[1].resolvedStartMinuteOfDay,575);
  assert.equal(after.blocks[1].resolvedEndMinuteOfDay,645);
 }finally{c.db.db.close();}
});

async function damagedFixture(){
 const c=await setup();
 const original=routine([block('Housework',570,660)]);await select(c,original);
 const source=(await c.service.materialize(c.user,day))!;await execute(c,source,source.blocks[0]);
 const replacement=nestedRoutine();await select(c,replacement,1);
 const rootID=crypto.randomUUID(),childID=crypto.randomUUID();
 const added:Plan['blocks']=replacement.blocks.map((b,index)=>{
  const start=index?575:540,end=index?645:690;
  return {id:index?childID:rootID,dayPlanID:source.id,sourceBlockID:b.id,parentBlockID:index?rootID:undefined,layerIndex:index,kind:'userDefined',title:b.title,reminders:[],timing:b.timing,isCancelled:false,resolvedStartMinuteOfDay:start,resolvedEndMinuteOfDay:end,startsAt:index?'2030-10-01T01:35:00Z':'2030-10-01T01:00:00Z',endsAt:index?'2030-10-01T02:45:00Z':'2030-10-01T03:30:00Z',tasks:b.taskBlueprints.map((t:any)=>({...t,id:crypto.randomUUID(),sourceTaskID:t.id,isCompleted:false}))};
 });
 const damaged={...source,sourceSavedTemplateID:replacement.id,revision:2,blocks:[...source.blocks,...added]};
 // Reproduce the old server's persisted merge, without weakening write APIs.
 await c.repo.apply(c.user,command('plan',source.id,damaged,1) as any,damaged);
 assert.throws(()=>validatePlanStructure(damaged));
 return {...c,source,damaged};
}

test('recovery previews, appends one version, preserves events and replays exactly',async()=>{
 const c=await damagedFixture();try{
  const operationID=crypto.randomUUID();
  const events=await c.repo.list(c.user,'execution');
  const preview=await c.service.repairPlan(c.user,c.source.id,2,1,operationID);
  assert.equal(preview.applied,false);assert.equal((await c.repo.get(c.user,'plan',c.source.id))!.revision,2);
  const result=await c.service.repairPlan(c.user,c.source.id,2,1,operationID,true);
  assert.equal(result.revision,3);assert.equal(result.applied,true);
  const replay=await c.service.repairPlan(c.user,c.source.id,2,1,operationID,true);assert.equal(replay.replayed,true);
  const after=(await c.service.materialize(c.user,day))!;validatePlanStructure(after);
  assert.deepEqual(wire(after.blocks),wire(c.source.blocks));assert.equal(after.sourceSavedTemplateID,c.source.sourceSavedTemplateID);
  assert.deepEqual(await c.repo.list(c.user,'execution'),events);
  assert.equal((await c.repo.db.all('SELECT * FROM operations WHERE userID=? AND kind=?',[c.user.id,'plan'])).length,3);
 }finally{c.db.db.close();}
});

test('recovery refuses to remove a block referenced by a new Note or execution',async()=>{
 for(const kind of ['note','execution']){
  const c=await damagedFixture();try{
   const added=c.damaged.blocks[1];
   if(kind==='execution')await execute(c,c.damaged,added);
   else{const id=crypto.randomUUID();await c.service.push(c.user,command('note',id,{id,text:'Keep me',blockInstanceID:added.id,occurredAt:now,timeZoneID:c.user.timeZoneID,createdAt:now,updatedAt:now,source:'ios'}));}
   await assert.rejects(c.service.repairPlan(c.user,c.source.id,2,1,crypto.randomUUID(),true),(e:any)=>e.code==='recovery_would_change_history');
   assert.equal((await c.repo.get(c.user,'plan',c.source.id))!.revision,2);
  }finally{c.db.db.close();}
 }
});

test('recovery rejects stale revisions and rolls back when a concurrent write arrives',async()=>{
 const c=await damagedFixture();try{
  await assert.rejects(c.service.repairPlan(c.user,c.source.id,3,1,crypto.randomUUID(),true),(e:any)=>e.code==='revision_conflict');
  const apply=c.repo.apply.bind(c.repo);
  c.repo.apply=async(user,op,body,statements)=>{
   if((op.kind as string)==='plan'){
    const id=crypto.randomUUID();
    await c.service.push(c.user,command('note',id,{id,text:'Arrived during recovery',blockInstanceID:c.damaged.blocks[1].id,occurredAt:now,timeZoneID:c.user.timeZoneID,createdAt:now,updatedAt:now,source:'ios'}));
   }
   return apply(user,op,body,statements);
  };
  await assert.rejects(c.service.repairPlan(c.user,c.source.id,2,1,crypto.randomUUID(),true),(e:any)=>e.code==='revision_conflict');
  assert.equal((await c.repo.get(c.user,'plan',c.source.id))!.revision,2);
  assert.equal((await c.repo.list(c.user,'note')).length,1);
 }finally{c.db.db.close();}
});
