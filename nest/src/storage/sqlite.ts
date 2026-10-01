import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import type { Database, Statement, Value } from './database.js';
export class SQLiteAdapter implements Database {
  readonly db: DatabaseSync;
  constructor(path: string) {
    this.db=new DatabaseSync(path);
    this.db.exec('PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;');
    this.db.exec('CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)');
    const directory=new URL('../../drizzle/',import.meta.url);
    for(const file of readdirSync(directory).filter(f=>f.endsWith('.sql')).sort()) {
      if(this.db.prepare('SELECT 1 FROM schema_migrations WHERE version=?').get(file))continue;
      this.db.exec('BEGIN IMMEDIATE');
      try {
        this.db.exec(readFileSync(new URL(file,directory),'utf8'));
        this.db.prepare('INSERT INTO schema_migrations VALUES(?)').run(file);
        this.db.exec('COMMIT');
      } catch(e) { this.db.exec('ROLLBACK'); throw e; }
    }
  }
  async all<T>(sql:string,args:Value[]=[]):Promise<T[]> { return this.db.prepare(sql).all(...args) as T[]; }
  async batch(statements:Statement[]):Promise<unknown[][]> {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const result=statements.map(s=>this.db.prepare(s.sql).all(...s.args??[]));
      this.db.exec('COMMIT');return result;
    } catch(e) { this.db.exec('ROLLBACK');throw e; }
  }
}
