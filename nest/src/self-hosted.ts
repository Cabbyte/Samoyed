import { Hono } from 'hono';
import { secureHeaders } from 'hono/secure-headers';
import { bodyLimit } from 'hono/body-limit';
import { readFileSync } from 'node:fs';
import { createApp } from './app.js';
import type { NestAuth,AuthConfig } from './auth.js';
import { nativeRedirect } from './auth.js';
import { DomainError } from './contracts.js';
import type { Repository } from './storage/repository.js';
const publicAuthPaths=new Set(['/get-session','/sign-out','/jwks','/passkey/generate-register-options','/passkey/verify-registration','/passkey/generate-authenticate-options','/passkey/verify-authentication','/passkey/list-user-passkeys','/passkey/update-passkey','/passkey/delete-passkey','/oauth2/authorize','/oauth2/token','/oauth2/consent','/oauth2/continue','/oauth2/revoke','/oauth2/introspect','/oauth2/userinfo','/.well-known/openid-configuration','/.well-known/oauth-authorization-server']);
export function selfHostedApp(repo:Repository,identity:NestAuth,config:AuthConfig,nativeClientID:string){
 const app=new Hono();
 app.use('*',bodyLimit({maxSize:512*1024,onError:c=>c.json({error:'request_too_large'},413)}));
 app.use('*',secureHeaders({referrerPolicy:'no-referrer',contentSecurityPolicy:{defaultSrc:["'self'"],scriptSrc:["'self'"],styleSrc:["'self'","'unsafe-inline'"],frameAncestors:["'none'"],baseUri:["'none'"],formAction:["'self'"]}}));
 app.onError((e,c)=>c.json({error:e instanceof DomainError?e.code:'internal_error'},e instanceof DomainError?e.status:500));
 app.get('/healthz',c=>c.json({status:'ok'}));
 app.get('/readyz',async c=>{await repo.db.all('SELECT 1 FROM nest_settings LIMIT 1');return c.json({status:'ready'});});
 app.get('/v1/capabilities',c=>c.json({protocolVersion:1,instanceID:config.instanceID,service:'Samoyed Nest',auth:{mode:'self-hosted',issuer:config.origin+'/api/auth',authorizationEndpoint:config.origin+'/api/auth/oauth2/authorize',tokenEndpoint:config.origin+'/api/auth/oauth2/token',revocationEndpoint:config.origin+'/api/auth/oauth2/revoke',clientID:nativeClientID,redirectURI:nativeRedirect,resource:identity.apiResource,scopes:['openid','profile','offline_access','nest:sync']},features:['routine','timeline-note','revision-sync'],releaseStatus:'acceptance-in-progress'}));
 for(const path of ['/','/login','/consent','/account'])app.get(path,c=>c.html(readFileSync(new URL('../web/index.html',import.meta.url),'utf8')));
 app.get('/assets/auth.js',c=>c.body(readFileSync(new URL('../web/auth.js',import.meta.url)),200,{'Content-Type':'text/javascript; charset=utf-8'}));
 app.use('/api/auth/*',async(c,next)=>{
  const requestID=crypto.randomUUID(),started=Date.now();c.header('X-Request-ID',requestID);await next();
  // Do not log query strings, request bodies, cookies, headers or auth error text.
  console.info(JSON.stringify({event:'auth_request',requestID,route:c.req.routePath,method:c.req.method,status:c.res.status,durationMs:Date.now()-started}));
 });
 app.all('/api/auth/*',async c=>{
  const path=new URL(c.req.url).pathname.slice('/api/auth'.length);
  if(!publicAuthPaths.has(path))return c.json({error:'not_found'},404);
  if(['/passkey/delete-passkey','/passkey/update-passkey'].includes(path)){
   const s=await identity.auth.api.getSession({headers:c.req.raw.headers});
   if(!s||Date.now()-new Date(s.session.createdAt).getTime()>300000)return c.json({error:'fresh_login_required'},403);
   if(path==='/passkey/delete-passkey'&&(await identity.auth.api.listPasskeys({headers:c.req.raw.headers})).length<=1)return c.json({error:'last_passkey_required'},409);
  }
  return identity.auth.handler(c.req.raw);
 });
 app.all('/.well-known/*',c=>identity.auth.handler(c.req.raw));
 for(const [path,kind] of [['device-sessions','device'],['agent-grants','agent']]){
  app.get('/v1/'+path,async c=>{const user=await identity.authenticate(c.req.raw)??await identity.browserUser(c.req.raw.headers);if(!user)return c.json({error:'unauthorized'},401);return c.json({items:identity.grants(user,kind)});});
  app.delete('/v1/'+path+'/:id',async c=>{
   let user=await identity.authenticate(c.req.raw);
   if(!user){if(c.req.header('origin')!==config.origin)return c.json({error:'forbidden'},403);user=await identity.browserUser(c.req.raw.headers);}
   if(!user)return c.json({error:'unauthorized'},401);identity.revoke(user,c.req.param('id')!,kind);return c.json({revoked:true});
  });
 }
 app.use('/mcp',async(c,next)=>{await next();if(c.res.status===401)c.header('WWW-Authenticate',`Bearer resource_metadata="${config.origin}/.well-known/oauth-protected-resource/mcp"`);});
 app.route('/',createApp({instanceID:config.instanceID,authMode:'self-hosted',repository:()=>repo,authenticate:r=>identity.authenticate(r,new URL(r.url).pathname==='/mcp'?identity.mcpResource:identity.apiResource)}));
 return app;
}
