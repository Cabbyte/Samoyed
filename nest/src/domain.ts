import { z } from 'zod/v3';
import { Temporal } from '@js-temporal/polyfill';
import { blockSchema, commandSchema, DomainError, effectiveTomorrow, instant, localDay, noteSchema, routineSchema, uuid, type User, wallTime } from './contracts.js';
import { Repository } from './storage/repository.js';
type Block=z.infer<typeof blockSchema>;
export function resolveBlocks(blocks:Block[]):Map<string,{start:number;end:number}> {
 const byID=new Map(blocks.map(b=>[b.id,b]));if(byID.size!==blocks.length)throw new DomainError('duplicate_block');
 for(const b of blocks) {
  const parent=b.parentTemplateBlockID?byID.get(b.parentTemplateBlockID):undefined;
  if((b.layerIndex===0 && b.parentTemplateBlockID)||(b.layerIndex>0&&!parent)||(parent&&b.layerIndex!==parent.layerIndex+1))throw new DomainError('invalid_parent');
  if(!parent && 'relative' in b.timing)throw new DomainError('relative_root');
  const visited=new Set([b.id]);let p=parent;
  while(p){if(visited.has(p.id))throw new DomainError('cycle');visited.add(p.id);p=p.parentTemplateBlockID?byID.get(p.parentTemplateBlockID):undefined;}
 }
 const ranges=new Map<string,{start:number;end:number}>();
 function children(parentID?:string) {
  const parent=parentID?ranges.get(parentID):undefined;
  const siblings=blocks.filter(b=>(b.parentTemplateBlockID??undefined)===parentID).map(block=>{
   const t=block.timing;
   const start='absolute' in t?t.absolute.startMinuteOfDay:parent!.start+t.relative.startOffsetMinutes;
   const end='absolute' in t?t.absolute.requestedEndMinuteOfDay:t.relative.requestedDurationMinutes==null?undefined:start+t.relative.requestedDurationMinutes;
   return {block,start,end};
  }).sort((a,b)=>a.start-b.start||a.block.id.localeCompare(b.block.id));
  for(const [i,s] of siblings.entries()) {
   const end=Math.min(parent?.end??1440,siblings[i+1]?.start??1440,s.end??1440);
   if(s.start>=end||(parent&&s.start<parent.start))throw new DomainError('invalid_block_range');
   ranges.set(s.block.id,{start:s.start,end});
  }
  for(const s of siblings)children(s.block.id);
 }
 children();return ranges;
}

// A merged snapshot must still resolve to its stored ranges. In particular, a
// retained root must not be shortened by a root from a different routine.
export function validatePlanStructure(plan:Plan):void {
 const blocks=plan.blocks.filter(b=>!b.isCancelled&&b.kind!=='blankBase');
 const ranges=resolveBlocks(blocks.map(b=>({id:b.id,parentTemplateBlockID:b.parentBlockID,layerIndex:b.layerIndex,title:b.title,timing:b.timing,taskBlueprints:[],reminders:[]})));
 const taskIDs=plan.blocks.flatMap(b=>b.tasks.map(t=>t.id));
 if(new Set(taskIDs).size!==taskIDs.length)throw new DomainError('duplicate_task');
 for(const block of blocks){
  const range=ranges.get(block.id)!;
  if(range.start!==block.resolvedStartMinuteOfDay||range.end!==block.resolvedEndMinuteOfDay)throw new DomainError('snapshot_range_mismatch');
 }
}

function rootOf(block:Plan['blocks'][number],byID:Map<string,Plan['blocks'][number]>):Plan['blocks'][number] {
 while(block.parentBlockID){
  const parent=byID.get(block.parentBlockID);
  if(!parent)throw new DomainError('invalid_parent');
  block=parent;
 }
 return block;
}

function frozenSubtrees(plan:Plan,executed:Set<string>):Plan['blocks'] {
 const byID=new Map(plan.blocks.map(b=>[b.id,b]));
 const roots=new Set(plan.blocks.filter(b=>
  Temporal.Instant.compare(Temporal.Instant.from(b.startsAt),Temporal.Now.instant())<=0||executed.has(b.id)||plan.correctionRevisions?.[b.id]
 ).map(b=>rootOf(b,byID).id));
 return plan.blocks.filter(b=>roots.has(rootOf(b,byID).id));
}
const weekdaySchema=z.object({weekday:z.number().int().min(1).max(7),savedTemplateID:uuid,effectiveFrom:localDay.optional()}).strict();
const exceptionSchema=z.object({date:localDay,savedTemplateID:uuid.nullable()}).strict();
const executionSchema=z.object({planID:uuid,planRevision:z.number().int().positive(),blockInstanceID:uuid,taskInstanceID:uuid,isCompleted:z.boolean(),occurredAt:instant,timeZoneID:z.string(),source:z.enum(['ios','agent','legacy']),correctionOperationID:uuid.optional()}).strict();
const correctionSchema=z.object({date:localDay,planID:uuid,planRevision:z.number().int().positive(),blockInstanceID:uuid,startMinuteOfDay:z.number().int().min(0).max(1439),endMinuteOfDay:z.number().int().min(1).max(1440),title:z.string().trim().min(1).max(500).optional(),note:z.string().max(20000).nullish(),tasks:z.array(z.object({id:uuid,sourceTaskID:uuid.nullish(),title:z.string().trim().min(1).max(500),order:z.number().int()}).strict()).max(100).optional()}).strict();
const legacyPlanSchema=z.object({id:uuid,date:localDay,source:z.literal('legacy'),sourceSavedTemplateID:uuid.nullish(),sourceRevision:z.number().int().positive().nullish(),revision:z.number().int().positive().nullish(),timeZoneID:z.string().nullish(),lastGeneratedAt:instant.nullish(),hasUserEdits:z.boolean(),blocks:z.array(z.object({id:uuid,dayPlanID:uuid.nullish(),sourceBlockID:uuid.nullish(),parentBlockID:uuid.nullish(),layerIndex:z.number().int().min(0).max(2),kind:z.enum(['userDefined','blankBase']),title:z.string().max(500),note:z.string().max(20000).nullish(),reminders:z.array(z.unknown()).max(20),timing:blockSchema.shape.timing,resolvedStartMinuteOfDay:z.number().int().min(0).max(1439).nullish(),resolvedEndMinuteOfDay:z.number().int().min(1).max(1440).nullish(),isCancelled:z.boolean(),tasks:z.array(z.object({id:uuid,sourceTaskID:uuid.nullish(),title:z.string().max(500),order:z.number().int(),isCompleted:z.boolean(),completedAt:instant.nullish()}).strict()).max(100)}).strict()).max(500)}).strict();
export class NestService {
 constructor(readonly repo:Repository,readonly audit?:(event:{operationID:string;kind:string;revision:number;replayed:boolean})=>void) {}
 async setTimeZone(user:User,zone:string,expectedZone:string,confirmed:boolean) {
  if(!confirmed)throw new DomainError('confirmation_required');
  Temporal.Now.zonedDateTimeISO(zone);
  if(user.timeZoneID===zone&&user.timeZoneConfirmed)return user;
  if(user.timeZoneID!==expectedZone)throw new DomainError('time_zone_conflict',409);
  const guardID=crypto.randomUUID(),account=await this.repo.get(user,'account','preferences');
  const body={id:user.id,timeZoneID:zone,timeZoneConfirmed:true};
  await this.repo.apply(user,{operationID:crypto.randomUUID(),kind:'account',entityID:'preferences',expectedRevision:account?.revision??0,deleted:false,payload:body} as any,body,[
   {sql:'INSERT INTO operation_guards VALUES(?,CASE WHEN EXISTS(SELECT 1 FROM users WHERE id=? AND timeZoneID=?) THEN 1 ELSE 0 END)',args:[guardID,user.id,expectedZone]},
   {sql:'UPDATE users SET timeZoneID=?,timeZoneConfirmed=1 WHERE id=?',args:[zone,user.id]},
   {sql:'DELETE FROM operation_guards WHERE id=?',args:[guardID]}
  ]);
  return body;
 }
 async push(user:User,input:unknown) {
  const op=commandSchema.parse(input);
  const receipt=await this.repo.receipt(user,op);if(receipt){this.audit?.({operationID:op.operationID,kind:op.kind,revision:receipt.revision,replayed:true});return receipt;}
  const old=await this.repo.get(user,op.kind,op.entityID);
  if((old?.revision??0)!==op.expectedRevision||old?.deleted)throw new DomainError('revision_conflict',409,{remote:old??null});
  if(op.deleted&&!old)throw new DomainError('not_found',404);
  let body:unknown;
  if(op.deleted){if(['routine','weekdayRule'].includes(op.kind)&&!user.timeZoneConfirmed)throw new DomainError('time_zone_setup_required');if(['execution','dayCorrection','legacyPlan','offlinePlan'].includes(op.kind))throw new DomainError('use_explicit_state');body=['routine','weekdayRule'].includes(op.kind)?{...old!.body as object,effectiveFrom:effectiveTomorrow(user.timeZoneID)}:old!.body;}
  else switch(op.kind) {
   case 'note': {
    const note=noteSchema.parse(op.payload);
    if(note.id!==op.entityID)throw new DomainError('identity_mismatch');
    if(note.blockInstanceID) {
      const plans=await this.repo.db.all<{body:string}>('SELECT body FROM operations WHERE userID=? AND kind IN (?,?,?)',[user.id,'plan','legacyPlan','offlinePlan']);
      if(!plans.some(p=>(JSON.parse(p.body) as Plan).blocks.some(b=>b.id===note.blockInstanceID)))throw new DomainError('unknown_block',404);
    }
    body={...note,createdAt:old?(old.body as typeof note).createdAt:new Date().toISOString(),updatedAt:new Date().toISOString(),revision:op.expectedRevision+1};break;
   }
   case 'routine': {
    const routine=routineSchema.parse(op.payload);if(!routine.effectiveFrom&&!user.timeZoneConfirmed)throw new DomainError('time_zone_setup_required');if(routine.id!==op.entityID)throw new DomainError('identity_mismatch');
    resolveBlocks(routine.blocks);
    const tasks=routine.blocks.flatMap(b=>b.taskBlueprints.map(t=>t.id));if(new Set(tasks).size!==tasks.length)throw new DomainError('duplicate_task');
    body={...routine,effectiveFrom:routine.effectiveFrom??effectiveTomorrow(user.timeZoneID),updatedAt:new Date().toISOString()};break;
   }
   case 'offlinePlan': {
    if(old||op.expectedRevision!==0)throw new DomainError('immutable_history',409);
    body=await this.restoreOfflinePlan(user,op.entityID,op.payload);break;
   }
   case 'legacyPlan': {
    if(old || op.expectedRevision!==0)throw new DomainError('immutable_history',409);
    const value=legacyPlanSchema.parse(op.payload);
    if(value.id!==op.entityID)throw new DomainError('identity_mismatch');
    // Preserve unknown source links and clock times as legacy; never infer a template by title.
    const ids=value.blocks.map(b=>b.id),tasks=value.blocks.flatMap(b=>b.tasks.map(t=>t.id));
    if(new Set(ids).size!==ids.length||new Set(tasks).size!==tasks.length)throw new DomainError('duplicate_identity');
    body={...value,revision:1};break;
   }
   case 'weekdayRule': {
    const rule=weekdaySchema.parse(op.payload);if(!rule.effectiveFrom&&!user.timeZoneConfirmed)throw new DomainError('time_zone_setup_required');if(String(rule.weekday)!==op.entityID)throw new DomainError('identity_mismatch');
    await this.requireRoutine(user,rule.savedTemplateID);body={...rule,effectiveFrom:rule.effectiveFrom??effectiveTomorrow(user.timeZoneID)};break;
   }
   case 'dateException': {
    const value=exceptionSchema.parse(op.payload);if(Temporal.PlainDate.from(value.date).toString()!==op.entityID)throw new DomainError('identity_mismatch');
    if(value.savedTemplateID)await this.requireRoutine(user,value.savedTemplateID);body=value;break;
   }
   case 'execution': {
    const value=executionSchema.parse(op.payload);if(value.taskInstanceID!==op.entityID)throw new DomainError('identity_mismatch');
    const plan=await this.planVersion(user,value.planID,value.planRevision);
    let known=plan.blocks.some(b=>b.id===value.blockInstanceID&&b.tasks.some(t=>t.id===value.taskInstanceID));
    if(value.correctionOperationID){
     const [row]=await this.repo.db.all<{body:string}>('SELECT body FROM operations WHERE userID=? AND operationID=? AND kind=?',[user.id,value.correctionOperationID,'dayCorrection']);
     if(!row)throw new DomainError('unknown_correction',409);
     const correction=correctionSchema.parse(JSON.parse(row.body));
     if(correction.planID!==value.planID||correction.blockInstanceID!==value.blockInstanceID||correction.planRevision>value.planRevision)throw new DomainError('correction_source_mismatch');
     known ||= correction.tasks?.some(t=>t.id===value.taskInstanceID)??false;
    }
    if(!known)throw new DomainError('unknown_task',404);
    body=value;break;
   }
   case 'dayCorrection': {
    const value=correctionSchema.parse(op.payload);if(op.entityID!==value.blockInstanceID)throw new DomainError('identity_mismatch');
    let plan=await this.planVersion(user,value.planID,value.planRevision);
    const currentPlan=await this.repo.get(user,'plan',value.planID)??await this.repo.get(user,'legacyPlan',value.planID)??await this.repo.get(user,'offlinePlan',value.planID);
    if(!currentPlan)throw new DomainError('unknown_plan_version',404);
    if(currentPlan.revision!==value.planRevision){
     const current=currentPlan.body as Plan;
     // Independent or successive corrections can share a cached plan base. A template
     // or timezone change still requires rereading and an explicit conflict choice.
     if(current.sourceSavedTemplateID!==plan.sourceSavedTemplateID||current.sourceRevision!==plan.sourceRevision||current.timeZoneID!==plan.timeZoneID||current.blocks.map(b=>b.id).sort().join()!==plan.blocks.map(b=>b.id).sort().join())throw new DomainError('stale_plan',409,{remote:currentPlan});
     plan=current;
    }
    if(Temporal.PlainDate.from(plan.date).toString()!==Temporal.PlainDate.from(value.date).toString())throw new DomainError('date_mismatch');
    const block=plan.blocks.find(b=>b.id===value.blockInstanceID);if(!block)throw new DomainError('unknown_block',404);
    if(value.tasks){
     const ids=value.tasks.map(t=>t.id);
     if(new Set(ids).size!==ids.length||plan.blocks.some(b=>b.id!==block.id&&b.tasks.some(t=>ids.includes(t.id))))throw new DomainError('duplicate_task');
     for(const t of value.tasks)if(t.sourceTaskID&&block.tasks.find(old=>old.id===t.id)?.sourceTaskID!==t.sourceTaskID)throw new DomainError('task_source_mismatch');
    }
    if(value.startMinuteOfDay>=value.endMinuteOfDay)throw new DomainError('invalid_block_range');
    // Corrections do not create blocks, replace IDs or overwrite task events.
    const candidates=plan.blocks.map(b=>({id:b.id,parentTemplateBlockID:b.parentBlockID,layerIndex:b.layerIndex,title:b.title,taskBlueprints:[],reminders:[],timing:{absolute:{startMinuteOfDay:b.id===block.id?value.startMinuteOfDay:b.resolvedStartMinuteOfDay,requestedEndMinuteOfDay:b.id===block.id?value.endMinuteOfDay:b.resolvedEndMinuteOfDay}}}));
    const ranges=resolveBlocks(candidates);
    if(candidates.some(b=>ranges.get(b.id)!.end!==b.timing.absolute.requestedEndMinuteOfDay))throw new DomainError('correction_overlap');
    body=value;break;
   }
  }
  const result=await this.repo.apply(user,op,body);
  this.audit?.({operationID:op.operationID,kind:op.kind,revision:result.revision,replayed:false});
  if(op.kind==='dayCorrection')await this.materialize(user,(body as z.infer<typeof correctionSchema>).date);
  return result;
 }
 private async restoreOfflinePlan(user:User,id:string,input:unknown):Promise<Plan> {
  const value=z.object({id:uuid,date:localDay,sourceSavedTemplateID:uuid,sourceRevision:z.number().int().positive(),sourceCursor:uuid,timeZoneID:z.string(),blocks:z.array(z.object({id:uuid,sourceBlockID:uuid,tasks:z.array(z.object({id:uuid,sourceTaskID:uuid})).max(100)})).max(200)}).parse(input);
  if(value.id!==id)throw new DomainError('identity_mismatch');
  const cache=await this.repo.scheduleCache(user,value.sourceCursor),active=new Map<string,{revision:number;body:any}>();
  for(const v of cache.versions){const b=v.body as any;if(b.effectiveFrom&&Temporal.PlainDate.compare(b.effectiveFrom,value.date)>0)continue;const key=v.kind+':'+v.id;if(v.deleted)active.delete(key);else active.set(key,{revision:v.revision,body:b});}
  const date=Temporal.PlainDate.from(value.date),selection=active.get('dateException:'+date.toString())?.body??active.get('weekdayRule:'+String(date.dayOfWeek%7+1))?.body;
  const routine=selection?.savedTemplateID?active.get('routine:'+selection.savedTemplateID):undefined;
  if(!routine||routine.body.id!==value.sourceSavedTemplateID||routine.revision!==value.sourceRevision||cache.timeZoneID!==value.timeZoneID)throw new DomainError('offline_source_mismatch');
  const source=routineSchema.parse(routine.body),ranges=resolveBlocks(source.blocks),ids=new Set([id,...value.blocks.map(b=>b.id),...value.blocks.flatMap(b=>b.tasks.map(t=>t.id))]);
  if(ids.size!==1+value.blocks.length+value.blocks.reduce((n,b)=>n+b.tasks.length,0)||new Set(value.blocks.map(b=>b.sourceBlockID)).size!==source.blocks.length||value.blocks.length!==source.blocks.length)throw new DomainError('duplicate_identity');
  const blocks=source.blocks.map(b=>{
   const supplied=value.blocks.find(x=>x.sourceBlockID===b.id),range=ranges.get(b.id)!;
   if(!supplied||supplied.tasks.length!==b.taskBlueprints.length||new Set(supplied.tasks.map(t=>t.sourceTaskID)).size!==b.taskBlueprints.length)throw new DomainError('offline_source_mismatch');
   return {id:supplied.id,dayPlanID:id,sourceBlockID:b.id,parentBlockID:value.blocks.find(x=>x.sourceBlockID===b.parentTemplateBlockID)?.id,layerIndex:b.layerIndex,kind:'userDefined',title:b.title,note:b.guidance??b.note??undefined,reminders:b.reminders,timing:b.timing,isCancelled:false,resolvedStartMinuteOfDay:range.start,resolvedEndMinuteOfDay:range.end,startsAt:wallTime(value.date,range.start,value.timeZoneID),endsAt:wallTime(value.date,range.end,value.timeZoneID),tasks:b.taskBlueprints.map(t=>{const task=supplied.tasks.find(x=>x.sourceTaskID===t.id);if(!task)throw new DomainError('offline_source_mismatch');return {...t,id:task.id,sourceTaskID:t.id,isCompleted:false};})};
  });
  // The cached cursor proves ownership and the exact historical scheduling rules.
  // Keep this snapshot separate if a newer cloud plan already exists for the date.
  return {id,date:value.date,source:'offline',sourceCursor:value.sourceCursor,sourceSavedTemplateID:source.id,sourceRevision:routine.revision,revision:1,timeZoneID:value.timeZoneID,lastGeneratedAt:new Date().toISOString(),hasUserEdits:false,blocks};
 }
 private async requireRoutine(user:User,id:string){const r=await this.repo.get(user,'routine',id);if(!r||r.deleted)throw new DomainError('unknown_routine',404);}
 private async planVersion(user:User,id:string,revision:number):Promise<Plan>{
  const [row]=await this.repo.db.all<{body:string}>('SELECT body FROM operations WHERE userID=? AND kind IN (?,?,?) AND entityID=? AND expectedRevision=?',[user.id,'plan','legacyPlan','offlinePlan',id,revision-1]);
  if(!row)throw new DomainError('unknown_plan_version',404);return JSON.parse(row.body);
 }
 async materialize(user:User,dateInput:unknown):Promise<Plan|undefined> {
  if(!user.timeZoneConfirmed)throw new DomainError('time_zone_setup_required');
  const date=localDay.parse(dateInput),day=Temporal.PlainDate.from(date),key=day.toString();
  const plans=await this.repo.list(user,'plan');const existing=plans.find(p=>Temporal.PlainDate.from((p.body as Plan).date).toString()===key);
  const executions=await this.repo.list(user,'execution');
  const previous=existing?.body as Plan|undefined;
  if(previous)validatePlanStructure(previous);
  const frozen=previous?frozenSubtrees(previous,new Set(executions.map(e=>(e.body as z.infer<typeof executionSchema>).blockInstanceID))):[];
  // A timezone change leaves today's started snapshot in its original timezone.
  if(previous&&frozen.length&&previous.timeZoneID!==user.timeZoneID)return this.applyCorrections(user,previous);
  const history=await this.repo.db.all<{kind:string;entityID:string;expectedRevision:number;deleted:number;body:string}>('SELECT kind,entityID,expectedRevision,deleted,body FROM operations WHERE userID=? AND kind IN (?,?,?) ORDER BY rowid',[user.id,'routine','weekdayRule','dateException']);
  const active=new Map<string,{revision:number;body:any}>();
  for(const v of history){const b=JSON.parse(v.body);if(b.effectiveFrom&&Temporal.PlainDate.compare(b.effectiveFrom,day)>0)continue;const k=v.kind+':'+v.entityID;if(v.deleted)active.delete(k);else active.set(k,{revision:v.expectedRevision+1,body:b});}
  const selection=active.get('dateException:'+key)?.body??active.get('weekdayRule:'+String(day.dayOfWeek%7+1))?.body;
  const routine=selection?.savedTemplateID?active.get('routine:'+selection.savedTemplateID):undefined;
  if(!routine){
   if(!previous)return undefined;
   if(previous.blocks.length===frozen.length)return this.applyCorrections(user,previous);
   const empty={...previous,sourceRevision:0,blocks:frozen,revision:previous.revision+1,lastGeneratedAt:new Date().toISOString()};
   validatePlanStructure(empty);
   await this.repo.apply(user,{operationID:crypto.randomUUID(),kind:'plan',entityID:empty.id,expectedRevision:previous.revision,deleted:false,payload:empty} as any,empty);
   return empty;
  }
  const source=routineSchema.parse(routine.body);
  if(existing&&(existing.body as Plan).sourceSavedTemplateID===source.id&&(existing.body as Plan).sourceRevision===routine.revision&&(existing.body as Plan).timeZoneID===user.timeZoneID)return this.applyCorrections(user,existing.body as Plan);
  const ranges=resolveBlocks(source.blocks),planID=existing?.id??await stableID(user.id+':'+key);
  const ids=new Map(source.blocks.map(b=>[b.id,previous?.blocks.find(old=>old.sourceBlockID===b.id)?.id??crypto.randomUUID()]));
  const plan:Plan={id:planID,date,sourceSavedTemplateID:source.id,sourceRevision:routine.revision,revision:(existing?.revision??0)+1,timeZoneID:user.timeZoneID,lastGeneratedAt:new Date().toISOString(),hasUserEdits:false,blocks:source.blocks.map(b=>{const r=ranges.get(b.id)!;return {id:ids.get(b.id)!,dayPlanID:planID,sourceBlockID:b.id,parentBlockID:b.parentTemplateBlockID?ids.get(b.parentTemplateBlockID):undefined,layerIndex:b.layerIndex,kind:'userDefined',title:b.title,note:b.guidance??b.note??undefined,reminders:b.reminders,timing:b.timing,isCancelled:false,resolvedStartMinuteOfDay:r.start,resolvedEndMinuteOfDay:r.end,startsAt:wallTime(date,r.start,user.timeZoneID),endsAt:wallTime(date,r.end,user.timeZoneID),tasks:b.taskBlueprints.map(t=>({...t,id:previous?.blocks.flatMap(b=>b.tasks).find(old=>old.sourceTaskID===t.id)?.id??crypto.randomUUID(),sourceTaskID:t.id,isCompleted:false}))};})};
  const freshByID=new Map(plan.blocks.map(b=>[b.id,b]));
  const frozenSources=new Set(frozen.map(b=>b.sourceBlockID));
  plan.blocks=[...frozen,...plan.blocks.filter(b=>!frozenSources.has(rootOf(b,freshByID).sourceBlockID))];
  try { validatePlanStructure(plan); }
  catch(error){
   // A conflicting selection must not corrupt the last usable, executed
   // snapshot. Keep its source metadata too; the selection rule stays intact.
   if(previous&&error instanceof DomainError)return this.applyCorrections(user,previous);
   throw error;
  }
  if(previous&&JSON.stringify(plan.blocks)===JSON.stringify(previous.blocks))return this.applyCorrections(user,previous);
  try { await this.repo.apply(user,{operationID:crypto.randomUUID(),kind:'plan',entityID:plan.id,expectedRevision:existing?.revision??0,deleted:false,payload:plan} as any,plan); }
  catch(error){if(error instanceof DomainError&&error.code==='revision_conflict'){const winner=await this.repo.get(user,'plan',plan.id);if(winner)return winner.body as Plan;}throw error;}
  return this.applyCorrections(user,plan);
 }

 // Explicit administrative recovery only. The old versions and every event
 // remain immutable; recovery is a new, revision-checked sync change.
 async repairPlan(user:User,planID:string,expectedRevision:number,sourceRevision:number,operationID:string,apply=false) {
  if(!Number.isInteger(expectedRevision)||!Number.isInteger(sourceRevision)||sourceRevision<1||sourceRevision>=expectedRevision)throw new DomainError('invalid_recovery_revision');
  uuid.parse(operationID);
  const [watermark]=await this.repo.db.all<{sequence:number}>('SELECT COALESCE(MAX(sequence),0) AS sequence FROM changes WHERE userID=?',[user.id]);
  const source=await this.planVersion(user,planID,sourceRevision);
  validatePlanStructure(source);
  const candidate={...source,revision:expectedRevision+1};
  const op={operationID,kind:'plan',entityID:planID,expectedRevision,deleted:false,payload:candidate} as any;
  const replay=await this.repo.receipt(user,op);
  if(replay)return {applied:true,replayed:true,revision:replay.revision,sourceRevision,blockCount:candidate.blocks.length};
  const current=await this.repo.get(user,'plan',planID);
  if(!current||current.deleted||current.revision!==expectedRevision)throw new DomainError('revision_conflict',409);
  const damaged=current.body as Plan;
  let invalid=false;try{validatePlanStructure(damaged);}catch(error){if(!(error instanceof DomainError))throw error;invalid=true;}
  if(!invalid)throw new DomainError('recovery_not_needed',409);
  const events=await this.repo.list(user,'execution'),notes=await this.repo.list(user,'note');
  const protectedIDs=new Set(damaged.blocks.filter(b=>Temporal.Instant.compare(Temporal.Instant.from(b.startsAt),Temporal.Now.instant())<=0).map(b=>b.id));
  for(const event of events){
   const value=event.body as z.infer<typeof executionSchema>;
   if(value.planID!==planID)continue;
   const block=candidate.blocks.find(b=>b.id===value.blockInstanceID);
   if(!block?.tasks.some(t=>t.id===value.taskInstanceID))throw new DomainError('recovery_would_change_history',409);
   protectedIDs.add(value.blockInstanceID);
  }
  for(const note of notes){
   const value=note.body as z.infer<typeof noteSchema>;
   if(value.blockInstanceID&&damaged.blocks.some(b=>b.id===value.blockInstanceID))protectedIDs.add(value.blockInstanceID);
  }
  if(JSON.stringify(damaged.correctionRevisions??{})!==JSON.stringify(source.correctionRevisions??{}))throw new DomainError('recovery_would_change_history',409);
  for(const id of protectedIDs){
   const before=damaged.blocks.find(b=>b.id===id),after=candidate.blocks.find(b=>b.id===id);
   if(!after||JSON.stringify(before)!==JSON.stringify(after))throw new DomainError('recovery_would_change_history',409);
  }
  if(apply){
   const guardID=crypto.randomUUID();
   await this.repo.apply(user,op,candidate,[
    {sql:'INSERT INTO operation_guards VALUES(?,CASE WHEN NOT EXISTS(SELECT 1 FROM changes WHERE userID=? AND sequence>? AND NOT(kind=? AND entityID=? AND revision=?)) THEN 1 ELSE 0 END)',args:[guardID,user.id,watermark.sequence,'plan',planID,expectedRevision+1]},
    {sql:'DELETE FROM operation_guards WHERE id=?',args:[guardID]}
   ]);
  }
  return {applied:apply,replayed:false,revision:candidate.revision,sourceRevision,blockCount:candidate.blocks.length,protectedBlockCount:protectedIDs.size};
 }
 private async applyCorrections(user:User,base:Plan):Promise<Plan>{
  const corrections=await this.repo.list(user,'dayCorrection');let changed=false;
  const plan=structuredClone(base);plan.correctionRevisions??={};
  for(const entity of corrections){
   const c=entity.body as z.infer<typeof correctionSchema>;
   if(entity.deleted||c.planID!==plan.id||c.planRevision>base.revision||(plan.correctionRevisions[entity.id]??0)>=entity.revision)continue;
   const block=plan.blocks.find(b=>b.id===c.blockInstanceID);if(!block)continue;
   // Correction validation uses absolute snapshot ranges. Preserve those same
   // ranges for descendants when changing their parent's start time.
   if(!changed)for(const item of plan.blocks)item.timing={absolute:{startMinuteOfDay:item.resolvedStartMinuteOfDay,requestedEndMinuteOfDay:item.resolvedEndMinuteOfDay}};
   block.resolvedStartMinuteOfDay=c.startMinuteOfDay;block.resolvedEndMinuteOfDay=c.endMinuteOfDay;
   block.timing={absolute:{startMinuteOfDay:c.startMinuteOfDay,requestedEndMinuteOfDay:c.endMinuteOfDay}};
   block.startsAt=wallTime(plan.date,c.startMinuteOfDay,plan.timeZoneID);block.endsAt=wallTime(plan.date,c.endMinuteOfDay,plan.timeZoneID);
   if(c.title!==undefined)block.title=c.title;if(c.note!==undefined)block.note=c.note??undefined;
   if(c.tasks)block.tasks=c.tasks.map(t=>({...t,sourceTaskID:t.sourceTaskID??undefined,isCompleted:block.tasks.find(old=>old.id===t.id)?.isCompleted??false}));
   plan.correctionRevisions[entity.id]=entity.revision;changed=true;
  }
  if(!changed)return base;
  validatePlanStructure(plan);
  plan.revision=base.revision+1;plan.hasUserEdits=true;
  await this.repo.apply(user,{operationID:crypto.randomUUID(),kind:'plan',entityID:plan.id,expectedRevision:base.revision,deleted:false,payload:plan} as any,plan);
  return plan;
 }
 async timeline(user:User,from:string,to:string,offset=0,limit=100,cursor?:string) {
  const start=Temporal.Instant.from(from),end=Temporal.Instant.from(to);if(Temporal.Instant.compare(start,end)>=0)throw new DomainError('invalid_range');
  const snapshot=await this.repo.timelineSnapshot(user,cursor);
  const notes=snapshot.entities.filter(e=>e.kind==='note'&&!e.deleted),plans=snapshot.entities.filter(e=>e.kind==='plan'&&!e.deleted);
  const legacy=snapshot.entities.filter(e=>(e.kind==='legacyPlan'||e.kind==='offlinePlan')&&!e.deleted&&(e.kind!=='offlinePlan'||snapshot.events.some(x=>(x.body as any).planID===e.id)||!plans.some(p=>Temporal.PlainDate.compare((p.body as Plan).date,(e.body as Plan).date)===0))).flatMap(e=>{
   const p=structuredClone(e.body) as z.infer<typeof legacyPlanSchema>,zone=p.timeZoneID??user.timeZoneID;
   for(const entity of snapshot.entities.filter(x=>x.kind==='dayCorrection'&&!x.deleted)){
    const c=entity.body as z.infer<typeof correctionSchema>;if(c.planID!==p.id)continue;
    const block=p.blocks.find(b=>b.id===c.blockInstanceID);if(!block)continue;
    block.resolvedStartMinuteOfDay=c.startMinuteOfDay;block.resolvedEndMinuteOfDay=c.endMinuteOfDay;
    if(c.title!==undefined)block.title=c.title;if(c.note!==undefined)block.note=c.note;
    if(c.tasks)block.tasks=c.tasks.map(t=>({...t,isCompleted:block.tasks.find(old=>old.id===t.id)?.isCompleted??false}));
   }
   e={...e,body:p};
   const a=Temporal.Instant.from(wallTime(p.date,0,zone)),b=Temporal.Instant.from(wallTime(p.date,1440,zone));
   if(Temporal.Instant.compare(a,end)>=0||Temporal.Instant.compare(b,start)<=0)return [];
   return [{kind:e.kind,id:e.id,occurredAt:Temporal.Instant.compare(a,start)<0?from:a.toString(),data:e}];
  });
  const items=[...notes.map(x=>({kind:'note',id:x.id,occurredAt:(x.body as z.infer<typeof noteSchema>).occurredAt,data:x})),
   ...plans.flatMap(p=>(p.body as Plan).blocks.map(b=>({kind:'block',id:b.id,occurredAt:b.startsAt,data:b}))),
   ...snapshot.events.map(x=>({kind:'execution',id:x.operationID,occurredAt:(x.body as z.infer<typeof executionSchema>).occurredAt,data:x})),...legacy]
   .filter(x=>Temporal.Instant.compare(Temporal.Instant.from(x.occurredAt),start)>=0&&Temporal.Instant.compare(Temporal.Instant.from(x.occurredAt),end)<0)
   .sort((a,b)=>Temporal.Instant.compare(Temporal.Instant.from(a.occurredAt),Temporal.Instant.from(b.occurredAt))||a.kind.localeCompare(b.kind)||a.id.localeCompare(b.id));
  const page=items.slice(offset,offset+limit);
  return {cursor:snapshot.cursor,items:page,nextOffset:items.length>offset+limit?offset+limit:null,legacyPlans:page.filter(x=>x.kind==='legacyPlan').map(x=>x.data)};
 }

}
export interface Plan {
 source?:string;sourceCursor?:string;
 correctionRevisions?:Record<string,number>;
 id:string;date:{year:number;month:number;day:number};sourceSavedTemplateID:string;sourceRevision:number;revision:number;timeZoneID:string;lastGeneratedAt:string;hasUserEdits:boolean;
 blocks:Array<{id:string;dayPlanID:string;sourceBlockID:string;parentBlockID?:string;layerIndex:number;kind:string;title:string;note?:string;reminders:unknown[];timing:Block['timing'];isCancelled:boolean;resolvedStartMinuteOfDay:number;resolvedEndMinuteOfDay:number;startsAt:string;endsAt:string;tasks:Array<{id:string;sourceTaskID?:string;title:string;order:number;isCompleted:boolean}>}>;
}

async function stableID(seed:string):Promise<string>{const digest=new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(seed)));digest[6]=(digest[6]&15)|80;digest[8]=(digest[8]&63)|128;const hex=Array.from(digest.slice(0,16),b=>b.toString(16).padStart(2,'0')).join('');return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;}
