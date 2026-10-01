import { z } from 'zod/v3';
import { Temporal } from '@js-temporal/polyfill';
export const uuid=z.string().uuid().transform(v=>v.toLowerCase());
export const timeZone=z.string().refine(v=>{try{Temporal.Now.zonedDateTimeISO(v);return true}catch{return false}},'Invalid IANA time zone');
export const instant=z.string().datetime({offset:true});
export const localDay=z.object({year:z.number().int().min(1970).max(2200),month:z.number().int().min(1).max(12),day:z.number().int().min(1).max(31)}).strict().refine(v=>{try{Temporal.PlainDate.from(v,{overflow:'reject'});return true}catch{return false}},'Invalid date');
export const noteSchema=z.object({id:uuid,text:z.string().trim().min(1).max(20000),occurredAt:instant,timeZoneID:timeZone,blockInstanceID:uuid.nullish(),createdAt:instant,updatedAt:instant,revision:z.number().int().nonnegative().optional(),source:z.enum(['ios','agent','legacy']),deletedAt:instant.nullish()}).strict();
const task=z.object({id:uuid,title:z.string().trim().min(1).max(500),order:z.number().int()}).strict();
const timing=z.union([
 z.object({absolute:z.object({startMinuteOfDay:z.number().int().min(0).max(1439),requestedEndMinuteOfDay:z.number().int().min(1).max(1440).nullish()}).strict()}).strict(),
 z.object({relative:z.object({startOffsetMinutes:z.number().int().min(0).max(1439),requestedDurationMinutes:z.number().int().min(1).max(1440).nullish()}).strict()}).strict()
]);
export const blockSchema=z.object({id:uuid,parentTemplateBlockID:uuid.nullish(),layerIndex:z.number().int().min(0).max(2),title:z.string().trim().min(1).max(500),note:z.string().max(20000).nullish(),guidance:z.string().max(20000).nullish(),reminders:z.array(z.unknown()).max(20).default([]),taskBlueprints:z.array(task).max(100).default([]),timing}).strict();
export const routineSchema=z.object({id:uuid,title:z.string().trim().min(1).max(500),sourceSuggestedTemplateID:uuid.nullish(),blocks:z.array(blockSchema).max(200),createdAt:instant,updatedAt:instant,effectiveFrom:localDay.optional()}).strict();
export const commandSchema=z.object({operationID:uuid,kind:z.enum(['note','routine','weekdayRule','dateException','dayCorrection','execution','legacyPlan','offlinePlan']),entityID:z.string().min(1).max(100),expectedRevision:z.number().int().nonnegative(),deleted:z.boolean().default(false),payload:z.unknown()}).strict();
export type Command=z.infer<typeof commandSchema>;
export interface Entity { kind:string; id:string; revision:number; deleted:boolean; body:unknown }
export interface User { id:string; timeZoneID:string; timeZoneConfirmed:boolean }
export function wallTime(date:{year:number;month:number;day:number},minute:number,zone:string):string {
 return Temporal.PlainDate.from(date).toPlainDateTime().add({minutes:minute}).toZonedDateTime(zone,{disambiguation:'compatible'}).toInstant().toString();
}
export function effectiveTomorrow(zone:string,now=Temporal.Now.instant()) {
 const day=now.toZonedDateTimeISO(zone).toPlainDate().add({days:1});return {year:day.year,month:day.month,day:day.day};
}
export class DomainError extends Error {constructor(public code:string,public status:400|401|403|404|409=400,public details?:unknown){super(code)}}
