import {sql} from 'drizzle-orm';
import {sqliteTable,text,integer,primaryKey,index,check} from 'drizzle-orm/sqlite-core';
export const users=sqliteTable('users',{id:text().primaryKey(),timeZoneID:text().notNull(),createdAt:text().notNull(),timeZoneConfirmed:integer().notNull().default(0)});
export const identities=sqliteTable('identities',{issuer:text().notNull(),subject:text().notNull(),userID:text().notNull().references(()=>users.id)},t=>[primaryKey({columns:[t.issuer,t.subject]})]);
export const entities=sqliteTable('entities',{userID:text().notNull().references(()=>users.id),kind:text().notNull(),id:text().notNull(),revision:integer().notNull(),deleted:integer().notNull(),body:text().notNull()},t=>[primaryKey({columns:[t.userID,t.kind,t.id]})]);
export const changes=sqliteTable('changes',{sequence:integer().primaryKey({autoIncrement:true}),userID:text().notNull(),kind:text().notNull(),entityID:text().notNull(),revision:integer().notNull(),deleted:integer().notNull(),body:text().notNull()},t=>[index('changes_user_sequence').on(t.userID,t.sequence)]);
export const operations=sqliteTable('operations',{userID:text().notNull(),operationID:text().notNull(),fingerprint:text().notNull(),kind:text().notNull(),entityID:text().notNull(),expectedRevision:integer().notNull(),deleted:integer().notNull(),body:text().notNull(),createdAt:text().notNull()},t=>[primaryKey({columns:[t.userID,t.operationID]})]);
export const cursors=sqliteTable('cursors',{id:text().primaryKey(),userID:text().notNull(),sequence:integer().notNull(),createdAt:text().notNull()},t=>[index('cursors_user_created').on(t.userID,t.createdAt)]);
export const deviceSessions=sqliteTable('device_sessions',{id:text().primaryKey(),userID:text().notNull().references(()=>users.id),tokenHash:text().notNull().unique(),refreshHash:text().notNull().unique(),expiresAt:text().notNull(),revokedAt:text()});
export const agentGrants=sqliteTable('agent_grants',{id:text().primaryKey(),userID:text().notNull().references(()=>users.id),provider:text().notNull(),subject:text().notNull(),revokedAt:text()});

export const operationGuards=sqliteTable('operation_guards',{id:text().primaryKey(),valid:integer().notNull()},t=>[check('valid_operation',sql`${t.valid} = 1`)]);
