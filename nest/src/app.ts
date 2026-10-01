import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { z, ZodError } from 'zod/v3';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
import { commandSchema, DomainError, instant, localDay, noteSchema, routineSchema, timeZone, uuid, type User } from './contracts.js';
import { NestService } from './domain.js';
import type { Repository } from './storage/repository.js';
export interface AppOptions {
 instanceID:string;
 repository:()=>Repository;
 authenticate:(request:Request,repo:Repository)=>Promise<User|undefined>;
 authMode:'sites'|'self-hosted';
}
export function createApp(options:AppOptions) {
 const app=new Hono();
 const requestIDs=new WeakMap<Request,string>();
 app.use('*',async(c,next)=>{
  const requestID=crypto.randomUUID(),started=Date.now();requestIDs.set(c.req.raw,requestID);c.header('X-Request-ID',requestID);
  await next();
  console.info(JSON.stringify({event:'request',requestID,method:c.req.method,route:c.req.routePath,status:c.res.status,durationMs:Date.now()-started}));
 });
 app.use('*',bodyLimit({maxSize:512*1024,onError:c=>c.json({error:'request_too_large'},413)}));
 app.onError((error,c)=>{
  const requestID=requestIDs.get(c.req.raw)??crypto.randomUUID();
  if(error instanceof DomainError)return c.json({error:error.code,details:error.details,requestID},error.status);
  if(error instanceof ZodError)return c.json({error:'invalid_request',issues:error.issues.map(i=>({path:i.path,code:i.code})),requestID},400);
  // Never log exception messages: drivers can include SQL parameter values or note text.
  console.error(JSON.stringify({requestID,error:'internal_error',route:c.req.routePath}));
  return c.json({error:'internal_error',requestID},500);
 });
 app.get('/',c=>c.html('<!doctype html><html><head><meta name="viewport" content="width=device-width"><title>Samoyed Nest</title></head><body><h1>Samoyed Nest</h1><p>Private beta under verification</p><p>Routine, offline execution and timeline notes.</p><a href="/signin-with-chatgpt?return_to=%2Fv1%2Fidentity">Sign in with ChatGPT</a></body></html>'));
 app.get('/v1/capabilities',c=>c.json({protocolVersion:1,instanceID:options.instanceID,service:'Samoyed Nest',auth:{mode:options.authMode,nativeDeviceAccess:'verification-required'},features:['routine','timeline-note','revision-sync'],releaseStatus:'not-accepted'}));
 async function context(request:Request){const repo=options.repository();const user=await options.authenticate(request,repo);if(!user)throw new DomainError('unauthorized',401);return {repo,user,service:new NestService(repo,event=>console.info(JSON.stringify({event:'operation',requestID:requestIDs.get(request),...event})))};}
 app.post('/v1/account/time-zone',async c=>{const {user,service}=await context(c.req.raw);const input=z.object({timeZoneID:timeZone,expectedTimeZoneID:timeZone,confirmed:z.literal(true)}).strict().parse(await c.req.json());return c.json(await service.setTimeZone(user,input.timeZoneID,input.expectedTimeZoneID,input.confirmed));});
 app.get('/v1/identity',async c=>{const {user}=await context(c.req.raw);return c.json({authenticated:true,user});});
 app.get('/v1/sync/bootstrap',async c=>{const {repo,user}=await context(c.req.raw);return c.json(await repo.bootstrap(user));});
 app.get('/v1/schedule-cache',async c=>{const {repo,user}=await context(c.req.raw);return c.json(await repo.scheduleCache(user));});
 app.get('/v1/sync/pull',async c=>{const {repo,user}=await context(c.req.raw);const q=z.object({cursor:z.string().uuid(),limit:z.coerce.number().int().min(1).max(500).default(100)}).parse(c.req.query());return c.json(await repo.pull(user,q.cursor,q.limit));});
 app.post('/v1/sync/push',async c=>{
  const {user,service}=await context(c.req.raw);const {operations}=z.object({operations:z.array(commandSchema).min(1).max(100)}).strict().parse(await c.req.json());
  const results=[];const blocked=new Set<string>();
  for(const op of operations){const key=op.kind+':'+op.entityID;
   if(blocked.has(key)){results.push({operationID:op.operationID,status:'blocked'});continue;}
   try{results.push({status:'accepted',...await service.push(user,op)});}
   catch(e){if(e instanceof DomainError){blocked.add(key);console.info(JSON.stringify({event:'operation_rejected',requestID:requestIDs.get(c.req.raw),operationID:op.operationID,error:e.code}));results.push({operationID:op.operationID,status:'rejected',error:e.code,details:e.details});}else if(e instanceof ZodError){blocked.add(key);results.push({operationID:op.operationID,status:'rejected',error:'invalid_request'});}else throw e;}
  }
  return c.json({results});
 });
 app.get('/v1/timeline',async c=>{const {user,service}=await context(c.req.raw);const q=z.object({from:instant,to:instant,cursor:z.string().uuid().optional(),offset:z.coerce.number().int().nonnegative().default(0),limit:z.coerce.number().int().min(1).max(500).default(100)}).parse(c.req.query());return c.json(await service.timeline(user,q.from,q.to,q.offset,q.limit,q.cursor));});
 app.post('/v1/plans/resolve',async c=>{const {user,service}=await context(c.req.raw);return c.json({plan:await service.materialize(user,await c.req.json())??null});});
 app.get('/native-probe/return',c=>{
  // Diagnostic only: no identity, session or authorization result is passed to the phone.
  const state=z.string().uuid().parse(c.req.query('state'));
  const authenticated=Boolean(c.req.header('oai-authenticated-user-id'));
  return c.redirect(`samoyed://nest-probe?state=${state}&browserAuthenticated=${authenticated}`);
 });
 app.all('/mcp',async c=>{
  // Authenticate discovery and initialization as well as tools/call.
  const authenticated = await context(c.req.raw);
  const server=new McpServer({name:'samoyed-nest',version:'0.1.0'});
  const read={readOnlyHint:true,destructiveHint:false,openWorldHint:false};
  const result=(data:unknown)=>({content:[{type:'text' as const,text:JSON.stringify(data)}]});
  const guarded=(fn:(ctx:Awaited<ReturnType<typeof context>>)=>Promise<unknown>)=>async()=>{try{return result(await fn(authenticated));}catch(e){if(e instanceof DomainError)return {...result({error:e.code,details:e.details}),isError:true};if(e instanceof ZodError)return {...result({error:'invalid_request'}),isError:true};throw e;}};
  server.registerTool('nest_connection_status',{description:'Read this Nest account and connection status.',inputSchema:{},annotations:read},guarded(async({user})=>({authenticated:true,user,instanceID:options.instanceID})));
  server.registerTool('set_account_time_zone',{description:'Initialize or change the shared schedule timezone only after the user confirms. Read account first for expectedTimeZoneID. Executed snapshots retain their original timezone.',inputSchema:{timeZoneID:timeZone,expectedTimeZoneID:timeZone,confirmed:z.literal(true)},annotations:{readOnlyHint:false,destructiveHint:false,idempotentHint:true,openWorldHint:false}},async args=>guarded(async({user,service})=>service.setTimeZone(user,args.timeZoneID,args.expectedTimeZoneID,args.confirmed))());
  server.registerTool('list_routines',{description:'Read saved routines with current revisions. Updates default to tomorrow in the account timezone.',inputSchema:{},annotations:read},guarded(async({user,repo})=>repo.list(user,'routine')));
  server.registerTool('read_entity',{description:'Read an owned routine, note, rule, correction or execution before editing; includes tombstones and revision.',inputSchema:{kind:commandSchema.shape.kind,entityID:z.string()},annotations:read},async args=>guarded(async({user,repo})=>await repo.get(user,args.kind,args.entityID)??null)());
  server.registerTool('save_note',{description:'Create or edit a pure-text timeline note. occurredAt determines placement; blockInstanceID is optional. expectedRevision=0 creates a new ID. Re-read on conflict.',inputSchema:{operationID:uuid,expectedRevision:z.number().int().nonnegative(),note:noteSchema},annotations:{readOnlyHint:false,destructiveHint:false,idempotentHint:true,openWorldHint:false}},async args=>guarded(async({user,service})=>service.push(user,{operationID:args.operationID,expectedRevision:args.expectedRevision,kind:'note',entityID:args.note.id,deleted:false,payload:args.note}))());
  server.registerTool('save_routine',{description:'Create or edit a versioned routine. Default effectiveFrom is tomorrow in the account timezone. Set it explicitly to change today. Existing execution history is retained.',inputSchema:{operationID:uuid,expectedRevision:z.number().int().nonnegative(),routine:routineSchema},annotations:{readOnlyHint:false,destructiveHint:false,idempotentHint:true,openWorldHint:false}},async args=>guarded(async({user,service})=>service.push(user,{operationID:args.operationID,expectedRevision:args.expectedRevision,kind:'routine',entityID:args.routine.id,deleted:false,payload:args.routine}))());
  server.registerTool('delete_entity',{description:'Delete a note, routine, weekday rule or date exception with a tombstone. Re-read first and provide expectedRevision. Routine deletion takes effect tomorrow; history and linked notes remain.',inputSchema:{operationID:uuid,kind:z.enum(['note','routine','weekdayRule','dateException']),entityID:z.string(),expectedRevision:z.number().int().positive()},annotations:{readOnlyHint:false,destructiveHint:true,idempotentHint:true,openWorldHint:false}},async args=>guarded(async({user,service})=>service.push(user,{...args,deleted:true,payload:null}))());
  server.registerTool('save_change',{description:'Create, update or delete a routine, weekday rule, date exception, existing-block correction, note or explicit task state. Supply stable operationID and expectedRevision. Routine edits default to tomorrow; set effectiveFrom for today. Read again on conflict; never retry with a guessed revision. Notes do not complete tasks.',inputSchema:commandSchema.shape,annotations:{readOnlyHint:false,destructiveHint:true,idempotentHint:true,openWorldHint:false}},async args=>guarded(async({user,service})=>service.push(user,args))());
  server.registerTool('resolve_day',{description:'Resolve a date using its exception or weekday rule. Retains executed snapshots and their source version.',inputSchema:localDay._def.schema.shape,annotations:{...read,readOnlyHint:false,idempotentHint:true}},async args=>guarded(async({user,service})=>({plan:await service.materialize(user,args)??null}))());
  server.registerTool('read_timeline',{description:'Read plans, execution events and notes by happened-time. Continue pages with the returned cursor and nextOffset to retain the same snapshot. Notes are only returned in this authorized query; they are not automatically sent as messages.',inputSchema:{from:instant,to:instant,cursor:z.string().uuid().optional(),offset:z.number().int().nonnegative().default(0),limit:z.number().int().min(1).max(500).default(100)},annotations:read},async args=>guarded(async({user,service})=>service.timeline(user,args.from,args.to,args.offset,args.limit,args.cursor))());
  const transport=new WebStandardStreamableHTTPServerTransport({sessionIdGenerator:undefined,enableJsonResponse:true});await server.connect(transport);return transport.handleRequest(c.req.raw);
 });
 return app;
}
