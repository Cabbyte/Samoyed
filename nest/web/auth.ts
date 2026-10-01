import { createAuthClient } from 'better-auth/client';
import { passkeyClient } from '@better-auth/passkey/client';
import { oauthProviderClient } from '@better-auth/oauth-provider/client';
const auth=createAuthClient({plugins:[passkeyClient(),oauthProviderClient()]});
const element=(id:string)=>document.getElementById(id)!;
const params=new URLSearchParams(location.search),oauthQuery=params.has('client_id')?location.search.slice(1):undefined;
const status=(text:string)=>{element('status').textContent=text;};
async function run(fn:()=>Promise<unknown>){status('处理中…');try{await fn();status('');}catch(e){status(e instanceof Error?e.message:'操作失败，请重试。');}}
async function post(path:string,body:unknown){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const v=await r.json();if(!r.ok)throw new Error(v.message??v.error??'请求失败');return v;}
function follow(value:any){const url=value.url??value.redirect_uri;if(typeof url!=='string')throw new Error('授权流程没有返回地址，请重新连接。');location.assign(url);}
async function refresh(){
 const {data}=await auth.getSession();const signed=!!data;
 element('login').hidden=signed;element('account').hidden=!signed;element('consent').hidden=true;
 if(oauthQuery&&location.pathname==='/login'&&(params.get('prompt')??'').split(' ').includes('login')){
  element('login').hidden=false;element('account').hidden=true;return;
 }
 if(!data)return;
 if(oauthQuery){
  element('account').hidden=true;
  if(location.pathname==='/consent'){
   element('consent').hidden=false;element('client').textContent='客户端：'+params.get('client_id');
   const labels:Record<string,string>={openid:'确认账户身份',profile:'读取账户资料',offline_access:'保持授权连接','nest:read':'读取 Routine、执行记录与 Note','nest:write':'修改 Routine 与 Note','nest:sync':'同步此设备上的日程与记录'};
   element('scopes').replaceChildren(...(params.get('scope')??'').split(' ').filter(Boolean).map(s=>{const li=document.createElement('li');li.textContent=labels[s]??s;return li;}));
  }else follow(await post('/api/auth/oauth2/continue',{oauth_query:oauthQuery,selected:true}));
  return;
 }
 element('name').textContent=data.user.name;
 const keys=await auth.passkey.listUserPasskeys();element('keys').replaceChildren();
 for(const k of keys.data??[]){const b=document.createElement('button');b.className='secondary';b.textContent='移除 '+(k.name||'Passkey');b.onclick=()=>run(async()=>{const r=await auth.passkey.deletePasskey({id:k.id});if(r.error)throw new Error(r.error.message);await refresh();});element('keys').append(b);}
 element('grants').replaceChildren();
 for(const [path,label] of [['device-sessions','设备'],['agent-grants','Agent']]){
  const r=await fetch('/v1/'+path);if(!r.ok)throw new Error('无法读取授权列表');const {items}=await r.json();
  for(const g of items){const b=document.createElement('button');b.className='secondary';b.textContent=g.revokedAt?label+' · 已撤销':label+' · '+g.clientID+' · 撤销';b.disabled=!!g.revokedAt;b.onclick=()=>run(async()=>{const r=await fetch('/v1/'+path+'/'+encodeURIComponent(g.id),{method:'DELETE'});if(!r.ok)throw new Error('撤销失败');await refresh();});element('grants').append(b);}
 }
}
element('signin').onclick=()=>run(async()=>{const r=await auth.signIn.passkey();if(r.error)throw new Error(r.error.message);if(oauthQuery)follow(r.data);else await refresh();});
element('register').onclick=()=>run(async()=>{const context=(element('invitation') as HTMLInputElement).value.trim();const r=await auth.passkey.addPasskey({context,createSession:true,name:'Primary Passkey'});if(r.error)throw new Error(r.error.message);history.replaceState(null,'',location.pathname+location.search);if(oauthQuery)follow(r.data);else await refresh();});
element('addkey').onclick=()=>run(async()=>{const r=await auth.passkey.addPasskey({name:'Additional Passkey'});if(r.error)throw new Error(r.error.message);await refresh();});
element('signout').onclick=()=>run(async()=>{await auth.signOut();await refresh();});
for(const [id,accept] of [['accept',true],['reject',false]] as const)element(id).onclick=()=>run(async()=>follow(await post('/api/auth/oauth2/consent',{oauth_query:oauthQuery,accept})));
if(location.hash.startsWith('#invite='))(element('invitation') as HTMLInputElement).value=decodeURIComponent(location.hash.slice(8));
void run(refresh);
