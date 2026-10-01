import { SQLiteAdapter } from './storage/sqlite.js';
import { Repository } from './storage/repository.js';
import { createNestAuth } from './auth.js';
import { migrateAuth } from './auth-storage.js';
import { backup } from 'node:sqlite';
const storage=new SQLiteAdapter(process.env.NEST_DATABASE??'/data/nest.sqlite');
try {
 const [command,arg]=process.argv.slice(2);
 if(command==='backup'&&arg){await backup(storage.db,arg);console.log('Backup completed');}
 else if(command==='invite'&&arg){
  migrateAuth(storage.db);
  const origin=process.env.NEST_ORIGIN!,secret=process.env.BETTER_AUTH_SECRET!,instanceID=process.env.NEST_INSTANCE_ID!;
  if(!origin||!secret||!instanceID)throw new Error('Configuration required');
  const identity=createNestAuth(storage.db,{origin,secret,instanceID},new Repository(storage));
  await identity.initialize();
  console.log(origin+'/login#invite='+identity.invite(arg));
 }else throw new Error('Usage: admin invite <display-name> | backup <destination>');
}finally{storage.db.close();}
