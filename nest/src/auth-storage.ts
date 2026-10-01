import { readFileSync,readdirSync } from 'node:fs';
import type { DatabaseSync } from 'node:sqlite';
export function migrateAuth(db:DatabaseSync){
 const dir=new URL('../auth-migrations/',import.meta.url);
 for(const name of readdirSync(dir).filter(n=>n.endsWith('.sql')).sort()){
  const version='auth/'+name;if(db.prepare('SELECT 1 FROM schema_migrations WHERE version=?').get(version))continue;
  db.exec('BEGIN IMMEDIATE');try{db.exec(readFileSync(new URL(name,dir),'utf8'));db.prepare('INSERT INTO schema_migrations VALUES(?)').run(version);db.exec('COMMIT');}catch(e){db.exec('ROLLBACK');throw e;}
 }
}
