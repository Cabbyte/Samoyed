import { createApp } from './app.js';
import { D1Adapter } from './storage/database.js';
import { Repository } from './storage/repository.js';
export default {
 async fetch(request:Request,env:{DB:D1Database}) {
  // This Site is an archive after the whole-service move. It can never become a second writer.
  const path=new URL(request.url).pathname;
  const archive={error:'site_archived_read_only',nestOrigin:'https://samoyed.protium.top'};
  if(path==='/v1/capabilities')return Response.json({protocolVersion:1,instanceID:'appgprj_6abe20b9f0688191ad0710e82fbcfff6',readOnly:true,...archive});
  if(path==='/')return new Response('<!doctype html><html><meta name="viewport" content="width=device-width"><title>Samoyed Nest Archive</title><h1>Samoyed Nest 只读档案</h1><p>此站点的业务写入已停用。</p><a href="https://samoyed.protium.top">打开 Samoyed Nest</a></html>',{headers:{'Content-Type':'text/html; charset=utf-8'}});
  if(path==='/v1/sync/bootstrap'||path==='/v1/sync/pull')return Response.json(archive,{status:423});
  if(request.method!=='GET'&&request.method!=='HEAD'){
   if(path!=='/mcp')return Response.json(archive,{status:423});
   const rpc=await request.clone().json().catch(()=>null) as any;
   if(rpc?.method==='tools/call'&&!['nest_connection_status','list_routines','read_entity','read_timeline'].includes(rpc.params?.name))return Response.json({jsonrpc:'2.0',id:rpc.id,result:{isError:true,content:[{type:'text',text:JSON.stringify(archive)}]}});
  }
  return createApp({instanceID:'appgprj_6abe20b9f0688191ad0710e82fbcfff6',repository:()=>new Repository(new D1Adapter(env.DB)),authenticate:async(request,repo)=>{
   // Only this Workers entry trusts dispatcher-injected identity headers.
   const subject=request.headers.get('oai-authenticated-user-id');if(!subject)return;
   const [user]=await repo.db.all<import('./contracts.js').User>('SELECT u.id,u.timeZoneID,u.timeZoneConfirmed FROM users u JOIN identities i ON i.userID=u.id WHERE i.issuer=? AND i.subject=?',['sites:appgprj_6abe20b9f0688191ad0710e82fbcfff6',subject]);
   return user?{...user,timeZoneConfirmed:!!user.timeZoneConfirmed}:undefined;
  }}).fetch(request);
 }
};
