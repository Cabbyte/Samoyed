import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { testDatabase } from './database.js';
import { Repository } from '../src/storage/repository.js';
import { NestService,resolveBlocks } from '../src/domain.js';
import { commandSchema,DomainError,wallTime } from '../src/contracts.js';
import { createApp } from '../src/app.js';
const now='2026-10-01T01:00:00Z';
const note=(id=crypto.randomUUID())=>({id,text:'Private note',occurredAt:now,timeZoneID:'Asia/Shanghai',createdAt:now,updatedAt:now,source:'ios'});
async function setup(){const db=await testDatabase();const repo=new Repository(db);const alice=await repo.identify('test','alice','Asia/Shanghai'),bob=await repo.identify('test','bob','UTC');return {db,repo,alice,bob,service:new NestService(repo)};}
function command(payload=note(),expectedRevision=0){return commandSchema.parse({operationID:crypto.randomUUID(),kind:'note',entityID:payload.id,expectedRevision,payload});}
test('retry after lost response returns original receipt and writes one change',async()=>{
 const {repo,service,alice,db}=await setup();const op=command();const first=await service.push(alice,op);assert.deepEqual(await service.push(alice,op),first);
 assert.equal((await db.all('SELECT * FROM changes')).length,1);
 await assert.rejects(service.push(alice,{...op,payload:{...op.payload as object,text:'Different'}}),(e:unknown)=>e instanceof DomainError&&e.code==='operation_id_reused');
 db.db.close();
});
test('concurrent same-note edits preserve winning value and reject stale revision',async()=>{
 const {repo,service,alice,db}=await setup();const op=command();await service.push(alice,op);
 const a={...op,operationID:crypto.randomUUID(),expectedRevision:1,payload:{...op.payload as object,text:'A'}};
 const b={...a,operationID:crypto.randomUUID(),payload:{...op.payload as object,text:'B'}};
 const results=await Promise.allSettled([service.push(alice,a),service.push(alice,b)]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal((await repo.get(alice,'note',op.entityID))?.revision,2);
 assert.equal((await db.all('SELECT * FROM operations')).length,2);db.db.close();
});
test('objects, cursors and operation IDs are scoped to authenticated user',async()=>{
 const {repo,service,alice,bob,db}=await setup();const op=command();await service.push(alice,op);assert.equal(await repo.get(bob,'note',op.entityID),undefined);
 const initial=await repo.bootstrap(alice);await assert.rejects(repo.pull(bob,initial.cursor));
 await service.push(bob,op);assert.equal((await repo.list(bob,'note')).length,1);assert.notEqual(alice.id,bob.id);db.db.close();
});
test('tombstone propagates and stale/new edits cannot resurrect deleted ID',async()=>{
 const {repo,service,alice,db}=await setup();const boot=await repo.bootstrap(alice),op=command();await service.push(alice,op);
 await service.push(alice,{...op,operationID:crypto.randomUUID(),expectedRevision:1,deleted:true});
 for(const expectedRevision of [0,1,2])await assert.rejects(service.push(alice,{...op,operationID:crypto.randomUUID(),expectedRevision}));
 const page=await repo.pull(alice,boot.cursor,1);assert.equal(page.hasMore,true);const next=await repo.pull(alice,page.cursor,1);assert.equal(next.changes[0].deleted,true);db.db.close();
});
test('bootstrap snapshot/cursor and pull include later writes exactly once',async()=>{
 const {repo,service,alice,db}=await setup();await service.push(alice,command());const boot=await repo.bootstrap(alice);assert.equal(boot.entities.length,1);
 await service.push(alice,command());const page=await repo.pull(alice,boot.cursor);assert.equal(page.changes.length,1);assert.equal((await repo.pull(alice,page.cursor)).changes.length,0);db.db.close();
});
test('HTTP ignores client-supplied ownership and blocks later commands for conflicted object',async()=>{
 const {repo,alice,db}=await setup();const app=createApp({instanceID:'test',repository:()=>repo,authenticate:async()=>alice});
 const op=command();let response=await app.request('/v1/sync/push',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operations:[{...op,userID:'bob'}]})});assert.equal(response.status,400);
 response=await app.request('/v1/sync/push',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operations:[{...op,expectedRevision:5},op]})});assert.deepEqual((await response.json() as {results:any[]}).results.map((r:any)=>r.status),['rejected','blocked']);db.db.close();
});
test('an unauthenticated deployment never accepts forged Sites headers in Node adapter',async()=>{
 const {repo,db}=await setup();const app=createApp({instanceID:'test',repository:()=>repo,authenticate:async()=>undefined});
 assert.equal((await app.request('/v1/sync/bootstrap',{headers:{'oai-authenticated-user-id':'alice'}})).status,401);db.db.close();
});
test('shared wall-time fixtures match gap/repetition/midnight policy',()=>{
 const cases=JSON.parse(readFileSync(new URL('../contracts/time-cases.json',import.meta.url),'utf8'));
 for(const c of cases)assert.equal(wallTime(c.date,c.minute,c.timeZoneID),c.instant,c.name);
});
test('note backdating changes placement but no checklist state or duration',async()=>{
 const {service,alice,db}=await setup();const op=command();await service.push(alice,op);const timeline=await service.timeline(alice,'2026-09-30T00:00:00Z','2026-10-02T00:00:00Z');assert.equal(timeline.items[0].kind,'note');assert.equal(timeline.items[0].occurredAt,now);db.db.close();
});

test('timeline pages retain a snapshot across edits, backdated inserts and deletion, with owner-scoped cursors',async()=>{
 const {service,alice,bob,db}=await setup();try{
  const a=command({...note(),occurredAt:'2026-10-01T01:00:00Z'}),b=command({...note(),occurredAt:'2026-10-01T02:00:00Z'});
  await service.push(alice,a);await service.push(alice,b);
  const first=await service.timeline(alice,'2026-10-01T00:00:00Z','2026-10-02T00:00:00Z',0,1);
  await service.push(alice,{...a,operationID:crypto.randomUUID(),expectedRevision:1,deleted:true});
  await service.push(alice,command({...note(),occurredAt:'2026-10-01T00:30:00Z'}));
  const second=await service.timeline(alice,'2026-10-01T00:00:00Z','2026-10-02T00:00:00Z',first.nextOffset!,1,first.cursor);
  assert.equal(second.items[0].id,b.entityID);assert.equal(second.nextOffset,null);
  await assert.rejects(service.timeline(bob,'2026-10-01T00:00:00Z','2026-10-02T00:00:00Z',0,1,first.cursor),(e:any)=>e.code==='invalid_cursor');
 }finally{db.db.close();}
});
