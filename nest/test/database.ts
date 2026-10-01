import { after } from 'node:test';
import { readFileSync,readdirSync } from 'node:fs';
import { Miniflare } from 'miniflare';
import { D1Adapter } from '../src/storage/database.js';
import { SQLiteAdapter } from '../src/storage/sqlite.js';
const instances:Miniflare[]=[];
after(async()=>{for(const mf of instances)await mf.dispose();});
export async function testDatabase() {
 if(process.env.NEST_TEST_DATABASE!=='d1')return new SQLiteAdapter(':memory:');
 const mf=new Miniflare({modules:true,script:'export default {fetch(){return new Response("ok")}}',compatibilityDate:'2026-07-30',d1Databases:['DB']});instances.push(mf);
 const binding=await mf.getD1Database('DB');
 const directory=new URL('../drizzle/',import.meta.url);
 for(const file of readdirSync(directory).filter(f=>f.endsWith('.sql')).sort()) {
  for(const sql of readFileSync(new URL(file,directory),'utf8').split('--> statement-breakpoint').filter(s=>s.trim()))await binding.prepare(sql).run();
 }
 const adapter=new D1Adapter(binding as unknown as D1Database);
 return {all:adapter.all.bind(adapter),batch:adapter.batch.bind(adapter),db:{close(){}}};
}
