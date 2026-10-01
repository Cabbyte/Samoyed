import type { Database, Statement } from './database.js';
import { DomainError, type Command, type Entity, type User } from '../contracts.js';
interface EntityRow {kind:string;id:string;revision:number;deleted:number;body:string}
interface ChangeRow {sequence:number;kind:string;entityID:string;revision:number;deleted:number;body:string}
const entity=(r:EntityRow):Entity=>({...r,deleted:!!r.deleted,body:JSON.parse(r.body)});
export class Repository {
 constructor(readonly db:Database) {}
 async identify(issuer:string,subject:string,zone?:string):Promise<User> {
  const id=crypto.randomUUID();
  await this.db.batch([
   {sql:'INSERT INTO users(id,timeZoneID,createdAt,timeZoneConfirmed) SELECT ?,?,?,? WHERE NOT EXISTS(SELECT 1 FROM identities WHERE issuer=? AND subject=?)',args:[id,zone??'UTC',new Date().toISOString(),zone?1:0,issuer,subject]},
   {sql:'INSERT INTO identities SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM users WHERE id=?) ON CONFLICT DO NOTHING',args:[issuer,subject,id,id]}
  ]);
  const [user]=await this.db.all<User>('SELECT u.id,u.timeZoneID,u.timeZoneConfirmed FROM users u JOIN identities i ON i.userID=u.id WHERE i.issuer=? AND i.subject=?',[issuer,subject]);
  if(!user)throw new DomainError('identity_unavailable',401);return {...user,timeZoneConfirmed:!!user.timeZoneConfirmed};
 }
 async get(user:User,kind:string,id:string):Promise<Entity|undefined> {
  const [row]=await this.db.all<EntityRow>('SELECT kind,id,revision,deleted,body FROM entities WHERE userID=? AND kind=? AND id=?',[user.id,kind,id]);return row&&entity(row);
 }
 async list(user:User,kind:string):Promise<Entity[]> { return (await this.db.all<EntityRow>('SELECT kind,id,revision,deleted,body FROM entities WHERE userID=? AND kind=? ORDER BY id',[user.id,kind])).map(entity); }
 async scheduleCache(user:User,cursor?:string) {
  if(!cursor){
   cursor=crypto.randomUUID();
   await this.db.batch([{sql:'INSERT INTO cursors VALUES(?,?,(SELECT COALESCE(MAX(sequence),0) FROM changes WHERE userID=?),?)',args:[cursor,user.id,user.id,new Date().toISOString()]}]);
  }
  const [position]=await this.db.all<{sequence:number}>('SELECT sequence FROM cursors WHERE id=? AND userID=?',[cursor,user.id]);
  if(!position)throw new DomainError('invalid_cursor');
  const rows=await this.db.all<EntityRow>("SELECT kind,entityID AS id,revision,deleted,body FROM changes WHERE userID=? AND sequence<=? AND kind IN ('routine','weekdayRule','dateException','account') ORDER BY sequence",[user.id,position.sequence]);
  const versions=rows.map(entity),account=versions.filter(v=>v.kind==='account').at(-1)?.body as User|undefined;
  return {cursor,timeZoneID:account?.timeZoneID??user.timeZoneID,versions};
 }
 async timelineSnapshot(user:User,cursor?:string) {
  if(!cursor){
   cursor=crypto.randomUUID();
   await this.db.batch([{sql:'INSERT INTO cursors VALUES(?,?,(SELECT COALESCE(MAX(sequence),0) FROM changes WHERE userID=?),?)',args:[cursor,user.id,user.id,new Date().toISOString()]}]);
  }
  const [position]=await this.db.all<{sequence:number}>('SELECT sequence FROM cursors WHERE id=? AND userID=?',[cursor,user.id]);
  if(!position)throw new DomainError('invalid_cursor',400);
  // Reconstruct the immutable change-log watermark instead of paging a moving live list.
  const rows=await this.db.all<EntityRow>(`SELECT c.kind,c.entityID AS id,c.revision,c.deleted,c.body FROM changes c
   WHERE c.userID=? AND c.sequence<=? AND c.sequence=(SELECT MAX(n.sequence) FROM changes n
   WHERE n.userID=c.userID AND n.kind=c.kind AND n.entityID=c.entityID AND n.sequence<=?)`,[user.id,position.sequence,position.sequence]);
  const events=await this.db.all<EntityRow&{operationID:string}>(`SELECT c.kind,c.entityID AS id,c.revision,c.deleted,c.body,o.operationID FROM changes c
   JOIN operations o ON o.userID=c.userID AND o.kind=c.kind AND o.entityID=c.entityID AND o.expectedRevision=c.revision-1
   WHERE c.userID=? AND c.kind='execution' AND c.sequence<=? ORDER BY c.sequence`,[user.id,position.sequence]);
  return {cursor,entities:rows.map(entity),events:events.map(row=>({...entity(row),operationID:row.operationID}))};
 }
 async receipt(user:User,op:Command) {
  const [row]=await this.db.all<{fingerprint:string;expectedRevision:number;body:string;deleted:number}>('SELECT fingerprint,expectedRevision,body,deleted FROM operations WHERE userID=? AND operationID=?',[user.id,op.operationID]);
  if(!row)return undefined;
  if(row.fingerprint!==await this.fingerprint(op))throw new DomainError('operation_id_reused',409);
  return {operationID:op.operationID,revision:row.expectedRevision+1,body:JSON.parse(row.body),deleted:!!row.deleted};
 }
 async apply(user:User,op:Command,body:unknown,additionalStatements:Statement[]=[]) {
  const existing=await this.receipt(user,op);if(existing)return existing;
  try {
   const guardID=crypto.randomUUID(),fingerprint=await this.fingerprint(op);
   await this.db.batch([
    {sql:`INSERT INTO operation_guards VALUES(?,CASE
      WHEN EXISTS(SELECT 1 FROM operations WHERE userID=? AND operationID=? AND fingerprint=?) THEN 1
      WHEN NOT EXISTS(SELECT 1 FROM operations WHERE userID=? AND operationID=?)
       AND COALESCE((SELECT revision FROM entities WHERE userID=? AND kind=? AND id=?),0)=?
       AND COALESCE((SELECT deleted FROM entities WHERE userID=? AND kind=? AND id=?),0)=0 THEN 1 ELSE 0 END)`,
     args:[guardID,user.id,op.operationID,fingerprint,user.id,op.operationID,user.id,op.kind,op.entityID,op.expectedRevision,user.id,op.kind,op.entityID]},
    {sql:'INSERT INTO operations VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(userID,operationID) DO NOTHING',args:[user.id,op.operationID,fingerprint,op.kind,op.entityID,op.expectedRevision,Number(op.deleted),JSON.stringify(body),new Date().toISOString()]},
    {sql:`INSERT INTO entities SELECT o.userID,o.kind,o.entityID,o.expectedRevision+1,o.deleted,o.body FROM operations o
      WHERE o.userID=? AND o.operationID=? AND COALESCE((SELECT revision FROM entities WHERE userID=o.userID AND kind=o.kind AND id=o.entityID),0)=o.expectedRevision
      ON CONFLICT(userID,kind,id) DO UPDATE SET revision=excluded.revision,deleted=excluded.deleted,body=excluded.body`,args:[user.id,op.operationID]},
    {sql:`INSERT INTO changes(userID,kind,entityID,revision,deleted,body) SELECT o.userID,o.kind,o.entityID,o.expectedRevision+1,o.deleted,o.body FROM operations o
      WHERE o.userID=? AND o.operationID=? AND NOT EXISTS(SELECT 1 FROM changes WHERE userID=o.userID AND kind=o.kind AND entityID=o.entityID AND revision=o.expectedRevision+1)`,args:[user.id,op.operationID]},
    {sql:'DELETE FROM operation_guards WHERE id=?',args:[guardID]},
    ...additionalStatements
   ]);
  } catch(error) {
   if(/CHECK constraint failed/.test(String(error))){const replay=await this.receipt(user,op);if(replay)return replay;}
   if(/revision_conflict|entity_deleted|CHECK constraint failed/.test(String(error)))throw new DomainError('revision_conflict',409,{remote:await this.get(user,op.kind,op.entityID)});
   throw error;
  }
  return (await this.receipt(user,op))!;
 }
 async bootstrap(user:User) {
  const cursor=crypto.randomUUID();
  const result=await this.db.batch([
   {sql:'INSERT INTO cursors VALUES(?,?,(SELECT COALESCE(MAX(sequence),0) FROM changes WHERE userID=?),?)',args:[cursor,user.id,user.id,new Date().toISOString()]},
   {sql:'SELECT kind,id,revision,deleted,body FROM entities WHERE userID=? ORDER BY kind,id',args:[user.id]}
  ]);
  return {user,entities:(result[1] as EntityRow[]).map(entity),cursor};
 }
 async pull(user:User,cursor:string,limit=100) {
  const [position]=await this.db.all<{sequence:number}>('SELECT sequence FROM cursors WHERE id=? AND userID=?',[cursor,user.id]);
  if(!position)throw new DomainError('invalid_cursor',400);
  const rows=await this.db.all<ChangeRow>('SELECT * FROM changes WHERE userID=? AND sequence>? ORDER BY sequence LIMIT ?',[user.id,position.sequence,limit+1]);
  const page=rows.slice(0,limit),next=crypto.randomUUID();
  await this.db.batch([{sql:'INSERT INTO cursors VALUES(?,?,?,?)',args:[next,user.id,page.at(-1)?.sequence??position.sequence,new Date().toISOString()]}]);
  return {cursor:next,hasMore:rows.length>limit,changes:page.map(r=>entity({...r,id:r.entityID}))};
 }
 private async fingerprint(op:Command) {
  // Canonicalize nested keys so wire whitespace and property ordering do not alter retries.
  const canonical=(v:unknown):unknown=>Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).sort(([a],[b])=>a.localeCompare(b)).map(([k,x])=>[k,canonical(x)])):v;
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(canonical(op))));
  return Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');
 }
}
