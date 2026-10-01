import { betterAuth } from 'better-auth';
import { APIError } from 'better-auth/api';
import { jwt } from 'better-auth/plugins';
import { passkey } from '@better-auth/passkey';
import { mcp } from '@better-auth/mcp';
import { cimd } from '@better-auth/cimd';
import { fetchClientMetadataResource } from '@better-auth/cimd/node';
import { createLocalJWKSet, jwtVerify } from 'jose';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import { DomainError, type User } from './contracts.js';
import type { Repository } from './storage/repository.js';

export interface AuthConfig { origin: string; secret: string; instanceID: string }
export const nativeRedirect = 'top.protium.samoyed:/oauth/callback';
const hash=(s:string)=>createHash('sha256').update(s).digest('hex');
type Invite={hash:string;userID:string;name:string;expiresAt:number;usedAt:number|null};
type Grant={id:string;userID:string;authUserID:string;referenceID:string;clientID:string;kind:string;revokedAt:string|null};

export function createNestAuth(db:DatabaseSync,config:AuthConfig,repo:Repository) {
 const apiResource=config.origin+'/v1',mcpResource=config.origin+'/mcp';
 function invitation(context?:string|null):Invite {
  if(!context || context.length>200)throw new APIError('FORBIDDEN',{message:'Invitation required'});
  const row=db.prepare('SELECT * FROM nest_invites WHERE hash=? AND expiresAt>? AND usedAt IS NULL').get(hash(context),Date.now()) as Invite|undefined;
  if(!row)throw new APIError('FORBIDDEN',{message:'Invitation expired or used'});return row;
 }
 const auth=betterAuth({
  appName:'Samoyed Nest',baseURL:config.origin,basePath:'/api/auth',secret:config.secret,database:db,
  logger:{disabled:true},trustedOrigins:[config.origin],
  session:{expiresIn:30*86400,cookieCache:{enabled:false}},
  advanced:{useSecureCookies:new URL(config.origin).protocol==='https:',ipAddress:{ipAddressHeaders:['x-real-ip']}},
  rateLimit:{enabled:true,storage:'database',window:60,max:100},
  plugins:[jwt(),passkey({rpID:new URL(config.origin).hostname,rpName:'Samoyed Nest',origin:config.origin,
   authenticatorSelection:{residentKey:'required',userVerification:'required'},
   registration:{requireSession:false,
    resolveUser:async({context})=>{const i=invitation(context);return {id:i.userID,name:i.name};},
    afterVerification:async({ctx,context,verification})=>{
     if(!verification.registrationInfo?.userVerified)throw new APIError('FORBIDDEN');
     if(ctx.context.session)return;
     const i=invitation(context),now=Date.now();
     db.exec('SAVEPOINT nest_invite');
     try {
      const claimed=db.prepare('UPDATE nest_invites SET usedAt=? WHERE hash=? AND usedAt IS NULL').run(now,i.hash);
      if(claimed.changes!==1)throw new APIError('FORBIDDEN');
      // Email is an internal placeholder required by the auth schema, never a login or merge key.
      db.prepare('INSERT INTO user(id,name,email,emailVerified,createdAt,updatedAt) VALUES(?,?,?,?,?,?)').run(i.userID,i.name,i.userID+'@accounts.invalid',0,now,now);
      db.exec('RELEASE nest_invite');return {userId:i.userID};
     }catch(e){db.exec('ROLLBACK TO nest_invite');db.exec('RELEASE nest_invite');throw e;}
    }
   },authentication:{afterVerification:async({verification})=>{if(!verification.authenticationInfo.userVerified)throw new APIError('FORBIDDEN');}}
  }),mcp({resource:mcpResource,resources:[mcpResource,apiResource],loginPage:'/login',consentPage:'/consent',
   scopes:['openid','profile','offline_access','nest:read','nest:write','nest:sync'],
   grantTypes:['authorization_code','refresh_token'],accessTokenExpiresIn:300,refreshTokenExpiresIn:30*86400,
   refreshTokenReuseInterval:30,allowDynamicClientRegistration:false,allowUnauthenticatedClientRegistration:false,
   clientPrivileges:async()=>false,
   postLogin:{page:'/consent',shouldRedirect:async()=>false,consentReferenceId:async({session})=>session.id},
   customAccessTokenClaims:async({user,referenceId})=>{
    if(!user||!referenceId)throw new APIError('UNAUTHORIZED');
    return {nest_reference:referenceId};
   }
  }),cimd({fetchClientMetadataResource,metadataProfile:'mcp-2026-07-28'})]
 });
 async function initialize() {
  const {adapter}=await auth.$context;
  let row=db.prepare("SELECT value FROM nest_settings WHERE key='nativeClientID'").get() as {value:string}|undefined;
  if(!row){
   const clientID='samoyed-ios-'+randomUUID();
   if(!await adapter.findOne({model:'oauthResource',where:[{field:'identifier',value:apiResource}]}))await adapter.create({model:'oauthResource',data:{identifier:apiResource,name:'Samoyed Sync',allowedScopes:['openid','profile','offline_access','nest:sync'],createdAt:new Date(),updatedAt:new Date()}});
   await adapter.create({model:'oauthClient',data:{clientId:clientID,name:'Samoyed iOS',redirectUris:[nativeRedirect],applicationType:'native',tokenEndpointAuthMethod:'none',grantTypes:['authorization_code','refresh_token'],responseTypes:['code'],scopes:['openid','profile','offline_access','nest:sync'],requirePKCE:true,skipConsent:false,disabled:false,createdAt:new Date(),updatedAt:new Date()}});
   await adapter.create({model:'oauthClientResource',data:{clientId:clientID,resourceId:apiResource,createdAt:new Date()}});
   db.prepare('INSERT INTO nest_settings VALUES(?,?)').run('nativeClientID',clientID);row={value:clientID};
  }
  return row.value;
 }
 async function authenticate(request:Request,resource=apiResource):Promise<User|undefined> {
  const token=request.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1];if(!token)return;
  try {
   const keys=await auth.api.getJwks();
   const {payload}=await jwtVerify(token,createLocalJWKSet(keys as Parameters<typeof createLocalJWKSet>[0]),{issuer:config.origin+'/api/auth',audience:resource,algorithms:['EdDSA','ES256','RS256']});
   const sub=payload.sub,ref=payload.nest_reference,client=payload.client_id;
   if(!sub||typeof ref!=='string'||typeof client!=='string')return;
   const scopes=new Set(typeof payload.scope==='string'?payload.scope.split(' '):[]);
   const nativeID=(db.prepare("SELECT value FROM nest_settings WHERE key='nativeClientID'").get() as {value:string}).value;
   if(resource===apiResource && (client!==nativeID||!scopes.has('nest:sync')))return;
   if(resource===mcpResource){
    if(client===nativeID||!scopes.has('nest:read'))return;
    if(request.method==='POST'){
     const rpc=await request.clone().json().catch(()=>null) as any;
     const reads=new Set(['nest_connection_status','list_routines','read_entity','read_timeline']);
     if(rpc?.method==='tools/call'&&!reads.has(rpc.params?.name)&&!scopes.has('nest:write'))return;
    }
   }
   const user=await repo.identify(config.origin+'/api/auth',sub);
   const id=hash(sub+'\0'+ref+'\0'+client),kind=resource===apiResource?'device':'agent';
   db.prepare('INSERT INTO nest_grants(id,userID,authUserID,referenceID,clientID,kind,createdAt) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING').run(id,user.id,sub,ref,client,kind,new Date().toISOString());
   const grant=db.prepare('SELECT * FROM nest_grants WHERE id=?').get(id) as Grant;
   if(grant.revokedAt)return;
   return user;
  }catch{return;}
 }
 async function browserUser(headers:Headers) {const s=await auth.api.getSession({headers});return s?repo.identify(config.origin+'/api/auth',s.user.id):undefined;}
 function grants(user:User,kind:string){return db.prepare('SELECT id,clientID,kind,createdAt,revokedAt FROM nest_grants WHERE userID=? AND kind=? ORDER BY createdAt DESC').all(user.id,kind);}
 function revoke(user:User,id:string,kind:string){
  const g=db.prepare('SELECT * FROM nest_grants WHERE id=? AND userID=? AND kind=?').get(id,user.id,kind) as Grant|undefined;
  if(!g)throw new DomainError('not_found',404);
  db.exec('BEGIN IMMEDIATE');try{
   db.prepare('UPDATE nest_grants SET revokedAt=COALESCE(revokedAt,?) WHERE id=?').run(new Date().toISOString(),id);
   db.prepare('DELETE FROM oauthAccessToken WHERE userId=? AND clientId=? AND referenceId=?').run(g.authUserID,g.clientID,g.referenceID);
   db.prepare('DELETE FROM oauthRefreshToken WHERE userId=? AND clientId=? AND referenceId=?').run(g.authUserID,g.clientID,g.referenceID);
   db.exec('COMMIT');
  }catch(e){db.exec('ROLLBACK');throw e;}
 }
 function invite(name:string){const token=Array.from(randomBytes(32),v=>v.toString(16).padStart(2,'0')).join('');db.prepare('INSERT INTO nest_invites(hash,userID,name,expiresAt) VALUES(?,?,?,?)').run(hash(token),randomUUID(),name,Date.now()+7*86400000);return token;}
 return {auth,initialize,authenticate,browserUser,grants,revoke,invite,apiResource,mcpResource};
}

export type NestAuth=ReturnType<typeof createNestAuth>;
