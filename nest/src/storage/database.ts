export type Value = string | number | null;
export interface Statement { sql: string; args?: Value[] }
export interface Database {
  all<T>(sql: string, args?: Value[]): Promise<T[]>;
  batch(statements: Statement[]): Promise<unknown[][]>;
}
export class D1Adapter implements Database {
  constructor(private readonly db: D1Database) {}
  async all<T>(sql: string, args: Value[] = []): Promise<T[]> {
    const result = await this.db.prepare(sql).bind(...args).all<T>();
    return result.results;
  }
  async batch(statements: Statement[]): Promise<unknown[][]> {
    const result = await this.db.batch(statements.map(s=>this.db.prepare(s.sql).bind(...s.args??[])));
    return result.map(r=>r.results);
  }
}
