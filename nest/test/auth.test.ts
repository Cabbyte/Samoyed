import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash,createHmac,randomUUID } from 'node:crypto';
import { SQLiteAdapter } from '../src/storage/sqlite.js';
import { Repository } from '../src/storage/repository.js';
import { createNestAuth,nativeRedirect } from '../src/auth.js';
import { migrateAuth } from '../src/auth-storage.js';
import { selfHostedApp } from '../src/self-hosted.js';
const origin='https://nest.example.test',secret='test-only-012345678901234567890123456789';
async function fixture(){
 const db=new SQLiteAdapter(':memory:');migrateAuth(db.db);const repo=new Repository(db),config={origin,secret,instanceID:'test'};
 const identity=createNestAuth(db.db,config,repo),client=await identity.initialize(),app=selfHostedApp(repo,identity,config,client);
 const ctx=await identity.auth.$context;
 async function session(name:string){const user=await ctx.internalAdapter.createUser({name,email:name+'@test.invalid',emailVerified:false},{method:'test'});const session=await ctx.internalAdapter.createSession(user.id);assert.ok(session);const signed=encodeURIComponent(session.token+'.'+createHmac('sha256',secret).update(session.token).digest('base64'));return {user,session,cookie:ctx.authCookies.sessionToken.name+'='+signed};}
 async function grant(cookie:string,clientID=client,resource=origin+'/v1',redirect=nativeRedirect,scope='openid profile offline_access nest:sync'){
  const verifier=createHash('sha256').update(randomUUID()).digest('hex'),challenge=createHash('sha256').update(verifier).digest('base64url');
  const q=new URLSearchParams({client_id:clientID,redirect_uri:redirect,response_type:'code',scope,resource,state:randomUUID(),code_challenge:challenge,code_challenge_method:'S256',prompt:'consent'});
  const r=await app.request(origin+'/api/auth/oauth2/authorize?'+q,{headers:{cookie}});
  assert.equal(r.status,302,await r.clone().text());const location=r.headers.get('location')!;assert.equal(new URL(location,origin).pathname,'/consent',new URL(location,origin).searchParams.get('error_description')??new URL(location,origin).searchParams.get('error')??'Unexpected redirect');
  const c=await app.request(origin+'/api/auth/oauth2/consent',{method:'POST',headers:{cookie,origin,'Content-Type':'application/json'},body:JSON.stringify({accept:true,oauth_query:new URL(location,origin).search.slice(1)})});
  assert.equal(c.status,200,await c.clone().text());const result=await c.json() as any;const code=new URL(result.redirect_uri??result.url).searchParams.get('code')!;assert.ok(code);
  return {code,verifier,clientID,resource,redirect};
 }
 async function exchange(g:Awaited<ReturnType<typeof grant>>,wrong=false){return app.request(origin+'/api/auth/oauth2/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'authorization_code',client_id:g.clientID,redirect_uri:g.redirect,code:g.code,code_verifier:wrong?'a'.repeat(64):g.verifier,resource:g.resource})});}
 return {db,identity,app,client,ctx,session,grant,exchange};
}
const authTest=process.env.NEST_TEST_DATABASE==='d1'?test.skip:test;
authTest('native OAuth exchanges PKCE, refreshes, scopes accounts and revokes a single device',async()=>{
 const f=await fixture();try{
  const alice=await f.session('alice'),bob=await f.session('bob');
  const ga=await f.grant(alice.cookie),gb=await f.grant(bob.cookie);
  const response=await f.exchange(ga);assert.equal(response.status,200,await response.clone().text());const token=await response.json() as any;
  assert.ok(token.refresh_token);assert.ok(token.access_token);
  const headers={authorization:'Bearer '+token.access_token};
  const r=await f.app.request(origin+'/v1/identity',{headers});assert.equal(r.status,200,await r.clone().text());
  const grantList=await (await f.app.request(origin+'/v1/device-sessions',{headers})).json() as any;assert.equal(grantList.items.length,1);
  const btoken=await (await f.exchange(gb)).json() as any;
  const bheaders={authorization:'Bearer '+btoken.access_token};
  assert.equal((await f.app.request(origin+'/v1/device-sessions/'+grantList.items[0].id,{method:'DELETE',headers:bheaders})).status,404);
  const refresh=await f.app.request(origin+'/api/auth/oauth2/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'refresh_token',client_id:f.client,refresh_token:token.refresh_token,resource:origin+'/v1'})});
  assert.equal(refresh.status,200,await refresh.clone().text());const renewed=await refresh.json() as any;
  assert.equal((await f.app.request(origin+'/mcp',{headers})).status,401);
  assert.equal((await f.app.request(origin+'/v1/device-sessions/'+grantList.items[0].id,{method:'DELETE',headers})).status,200);
  assert.equal((await f.app.request(origin+'/v1/identity',{headers:{authorization:'Bearer '+renewed.access_token}})).status,401);
  assert.equal((await f.app.request(origin+'/v1/identity',{headers:bheaders})).status,200);
  const revokedRefresh=await f.app.request(origin+'/api/auth/oauth2/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'refresh_token',client_id:f.client,refresh_token:renewed.refresh_token,resource:origin+'/v1'})});assert.equal(revokedRefresh.status,400);
 }finally{f.db.db.close();}
});
authTest('native OAuth rejects wrong PKCE and unauthenticated account administration',async()=>{
 const f=await fixture();try{
  const a=await f.session('alice');const g=await f.grant(a.cookie);
  assert.ok([400,401].includes((await f.exchange(g,true)).status));
  assert.equal((await f.app.request(origin+'/v1/sync/bootstrap',{headers:{'oai-authenticated-user-id':a.user.id}})).status,401);
  assert.equal((await f.app.request(origin+'/api/auth/admin/oauth2/create-client',{method:'POST'})).status,404);
  const unauth=await f.app.request(origin+'/api/auth/passkey/generate-register-options');assert.ok(unauth.status>=400);
  const capability=await (await f.app.request(origin+'/v1/capabilities')).json() as any;assert.equal(capability.auth.clientID,f.client);
 }finally{f.db.db.close();}
});
authTest('MCP discovery, resource isolation and independent Agent revocation',async()=>{
 const f=await fixture();try{
  const {adapter}=f.ctx,clientID='test-agent',redirect='https://client.example.test/callback',resource=origin+'/mcp';
  await adapter.create({model:'oauthClient',data:{clientId:clientID,name:'Test Agent',redirectUris:[redirect],applicationType:'web',tokenEndpointAuthMethod:'none',grantTypes:['authorization_code','refresh_token'],responseTypes:['code'],scopes:['openid','offline_access','nest:read','nest:write'],requirePKCE:true,skipConsent:false,disabled:false,createdAt:new Date(),updatedAt:new Date()}});
  await adapter.create({model:'oauthClientResource',data:{clientId:clientID,resourceId:resource,createdAt:new Date()}});
  const a=await f.session('alice');
  const ag=await f.grant(a.cookie,clientID,resource,redirect,'openid offline_access nest:read nest:write');
  const r=await f.exchange(ag);assert.equal(r.status,200,await r.clone().text());const token=await r.json() as any;
  const native=await(await f.exchange(await f.grant(a.cookie))).json() as any;
  const headers={authorization:'Bearer '+token.access_token,'Content-Type':'application/json',accept:'application/json, text/event-stream'};
  const call=await f.app.request(origin+'/mcp',{method:'POST',headers,body:JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'nest_connection_status',arguments:{}}})});
  assert.equal(call.status,200,await call.clone().text());assert.equal((await call.json() as any).result.isError,undefined);
  assert.equal((await f.app.request(origin+'/v1/sync/bootstrap',{headers})).status,401);
  const list=await(await f.app.request(origin+'/v1/agent-grants',{headers:{cookie:a.cookie}})).json() as any;
  assert.equal(list.items.length,1);
  const revoke=await f.app.request(origin+'/v1/agent-grants/'+list.items[0].id,{method:'DELETE',headers:{cookie:a.cookie,origin}});assert.equal(revoke.status,200);
  assert.equal((await f.app.request(origin+'/mcp',{method:'POST',headers,body:'{}'})).status,401);
  assert.equal((await f.app.request(origin+'/v1/identity',{headers:{authorization:'Bearer '+native.access_token}})).status,200);
  const discovery=await f.app.request(origin+'/.well-known/oauth-authorization-server/api/auth');assert.equal(discovery.status,200);
  const metadata=await discovery.json() as any;assert.equal(metadata.issuer,origin+'/api/auth');assert.equal(metadata.authorization_response_iss_parameter_supported,true);
  const protectedResource=await f.app.request(origin+'/.well-known/oauth-protected-resource/mcp');assert.equal(protectedResource.status,200);
  assert.equal((await protectedResource.json() as any).resource,resource);
 }finally{f.db.db.close();}
});
