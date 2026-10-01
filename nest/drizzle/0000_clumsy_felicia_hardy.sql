CREATE TABLE `agent_grants` (
	`id` text PRIMARY KEY NOT NULL,
	`userID` text NOT NULL,
	`provider` text NOT NULL,
	`subject` text NOT NULL,
	`revokedAt` text,
	FOREIGN KEY (`userID`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `changes` (
	`sequence` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`userID` text NOT NULL,
	`kind` text NOT NULL,
	`entityID` text NOT NULL,
	`revision` integer NOT NULL,
	`deleted` integer NOT NULL,
	`body` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `changes_user_sequence` ON `changes` (`userID`,`sequence`);--> statement-breakpoint
CREATE TABLE `cursors` (
	`id` text PRIMARY KEY NOT NULL,
	`userID` text NOT NULL,
	`sequence` integer NOT NULL,
	`createdAt` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `cursors_user_created` ON `cursors` (`userID`,`createdAt`);--> statement-breakpoint
CREATE TABLE `device_sessions` (
	`id` text PRIMARY KEY NOT NULL,
	`userID` text NOT NULL,
	`tokenHash` text NOT NULL,
	`refreshHash` text NOT NULL,
	`expiresAt` text NOT NULL,
	`revokedAt` text,
	FOREIGN KEY (`userID`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `device_sessions_tokenHash_unique` ON `device_sessions` (`tokenHash`);--> statement-breakpoint
CREATE UNIQUE INDEX `device_sessions_refreshHash_unique` ON `device_sessions` (`refreshHash`);--> statement-breakpoint
CREATE TABLE `entities` (
	`userID` text NOT NULL,
	`kind` text NOT NULL,
	`id` text NOT NULL,
	`revision` integer NOT NULL,
	`deleted` integer NOT NULL,
	`body` text NOT NULL,
	PRIMARY KEY(`userID`, `kind`, `id`),
	FOREIGN KEY (`userID`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `identities` (
	`issuer` text NOT NULL,
	`subject` text NOT NULL,
	`userID` text NOT NULL,
	PRIMARY KEY(`issuer`, `subject`),
	FOREIGN KEY (`userID`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `operations` (
	`userID` text NOT NULL,
	`operationID` text NOT NULL,
	`fingerprint` text NOT NULL,
	`kind` text NOT NULL,
	`entityID` text NOT NULL,
	`expectedRevision` integer NOT NULL,
	`deleted` integer NOT NULL,
	`body` text NOT NULL,
	`createdAt` text NOT NULL,
	PRIMARY KEY(`userID`, `operationID`)
);
--> statement-breakpoint
CREATE TABLE `users` (
	`id` text PRIMARY KEY NOT NULL,
	`timeZoneID` text NOT NULL,
	`createdAt` text NOT NULL
);
