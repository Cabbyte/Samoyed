import { SQLiteAdapter } from './storage/sqlite.js';
import { Repository } from './storage/repository.js';
import { createNestAuth } from './auth.js';
import { migrateAuth } from './auth-storage.js';
import { backup } from 'node:sqlite';
import { NestService } from './domain.js';
import type { User } from './contracts.js';
const storage=new SQLiteAdapter(process.env.NEST_DATABASE??'/data/nest.sqlite');
try {
 const [command,arg,...rest]=process.argv.slice(2);
 if(command==='backup'&&arg){await backup(storage.db,arg);console.log('Backup completed');}
 else if(command==='repair-plan'&&arg){
  const [expected,source,operationID,mode]=rest;
  if(!operationID||(mode!==undefined&&mode!=='--apply'))throw new Error('Usage: admin repair-plan <plan-id> <expected-revision> <source-revision> <operation-id> [--apply]');
  const owners=await storage.all<User>('SELECT u.id,u.timeZoneID,u.timeZoneConfirmed FROM users u JOIN entities e ON e.userID=u.id WHERE e.kind=? AND e.id=?',['plan',arg]);
  if(owners.length!==1)throw new Error('Expected one plan owner');
  console.log(JSON.stringify(await new NestService(new Repository(storage)).repairPlan(owners[0],arg,Number(expected),Number(source),operationID,mode==='--apply')));
 }
 else if(command==='invite'&&arg){
  migrateAuth(storage.db);
  const origin=process.env.NEST_ORIGIN!,secret=process.env.BETTER_AUTH_SECRET!,instanceID=process.env.NEST_INSTANCE_ID!;
  if(!origin||!secret||!instanceID)throw new Error('Configuration required');
  const identity=createNestAuth(storage.db,{origin,secret,instanceID},new Repository(storage));
  await identity.initialize();
  console.log(origin+'/login#invite='+identity.invite(arg));
 }else throw new Error('Usage: admin invite <display-name> | backup <destination> | repair-plan <plan-id> <expected-revision> <source-revision> <operation-id> [--apply]');
}finally{storage.db.close();}
