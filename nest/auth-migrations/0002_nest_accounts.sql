CREATE TABLE nest_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE nest_invites (hash TEXT PRIMARY KEY, userID TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
 expiresAt INTEGER NOT NULL, usedAt INTEGER);
CREATE TABLE nest_grants (id TEXT PRIMARY KEY, userID TEXT NOT NULL REFERENCES users(id),
 authUserID TEXT NOT NULL REFERENCES user(id), referenceID TEXT NOT NULL, clientID TEXT NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('device','agent')), createdAt TEXT NOT NULL, revokedAt TEXT);
CREATE INDEX nest_grants_owner ON nest_grants(userID,kind);
