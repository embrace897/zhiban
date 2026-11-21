PRAGMA foreign_keys=ON;
PRAGMA journal_mode=WAL;
CREATE TABLE users(
 id TEXT PRIMARY KEY,
 wx_subject TEXT NOT NULL UNIQUE,
 role TEXT NOT NULL CHECK(role IN ('student','maintainer','admin')),
 status TEXT NOT NULL DEFAULT 'active',
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE files(
 id TEXT PRIMARY KEY,
 owner_id TEXT NOT NULL REFERENCES users(id),
 storage_key TEXT NOT NULL UNIQUE,
 sha256 TEXT NOT NULL,
 mime TEXT NOT NULL,
 size_bytes INTEGER NOT NULL CHECK(size_bytes>=0),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE notices(
 id TEXT PRIMARY KEY,
 owner_id TEXT NOT NULL REFERENCES users(id),
 file_id TEXT REFERENCES files(id),
 source TEXT NOT NULL,
 published_at TEXT,
 raw_text TEXT,
 status TEXT NOT NULL DEFAULT 'pending',
 revision INTEGER NOT NULL DEFAULT 1,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE drafts(
 id TEXT PRIMARY KEY,
 notice_id TEXT NOT NULL REFERENCES notices(id),
 revision INTEGER NOT NULL,
 fields_json TEXT NOT NULL,
 evidence_json TEXT NOT NULL,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(notice_id,revision)
);
CREATE TABLE affairs(
 id TEXT PRIMARY KEY,
 owner_id TEXT NOT NULL REFERENCES users(id),
 title TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'preparing',
 revision INTEGER NOT NULL DEFAULT 1,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE affair_notices(
 affair_id TEXT NOT NULL REFERENCES affairs(id),
 notice_id TEXT NOT NULL REFERENCES notices(id),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(affair_id,notice_id)
);
CREATE TABLE events(
 id TEXT PRIMARY KEY,
 owner_id TEXT NOT NULL REFERENCES users(id),
 affair_id TEXT NOT NULL REFERENCES affairs(id),
 title TEXT NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('activity','deadline','step')),
 due_at TEXT,
 date_value TEXT,
 precision TEXT NOT NULL CHECK(precision IN ('date','minute','unknown')),
 timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
 status TEXT NOT NULL DEFAULT 'todo',
 revision INTEGER NOT NULL DEFAULT 1,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK((precision='date' AND date_value IS NOT NULL AND due_at IS NULL) OR (precision='minute' AND due_at IS NOT NULL AND date_value IS NULL) OR (precision='unknown' AND due_at IS NULL AND date_value IS NULL))
);
CREATE TABLE checklist_items(
 id TEXT PRIMARY KEY,
 affair_id TEXT NOT NULL REFERENCES affairs(id),
 title TEXT NOT NULL,
 done INTEGER NOT NULL DEFAULT 0 CHECK(done IN (0,1)),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE plans(
 id TEXT PRIMARY KEY,
 owner_id TEXT NOT NULL REFERENCES users(id),
 affair_id TEXT NOT NULL REFERENCES affairs(id),
 revision INTEGER NOT NULL,
 operations_json TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'draft',
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE confirmations(
 id TEXT PRIMARY KEY,
 plan_id TEXT NOT NULL REFERENCES plans(id),
 plan_revision INTEGER NOT NULL,
 actor_id TEXT NOT NULL REFERENCES users(id),
 digest TEXT NOT NULL,
 consumed INTEGER NOT NULL DEFAULT 0 CHECK(consumed IN (0,1)),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(plan_id,plan_revision)
);
CREATE TABLE executions(
 id TEXT PRIMARY KEY,
 plan_id TEXT NOT NULL REFERENCES plans(id),
 step_key TEXT NOT NULL UNIQUE,
 tool TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'queued',
 result_json TEXT,
 lease_until TEXT,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE reminders(
 id TEXT PRIMARY KEY,
 event_id TEXT NOT NULL REFERENCES events(id),
 fire_at TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'pending',
 read_at TEXT,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE knowledge_documents(
 id TEXT PRIMARY KEY,
 file_id TEXT NOT NULL REFERENCES files(id),
 institution TEXT NOT NULL,
 version TEXT NOT NULL,
 source_url TEXT,
 valid_until TEXT,
 status TEXT NOT NULL DEFAULT 'draft',
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE knowledge_chunks(
 id TEXT PRIMARY KEY,
 document_id TEXT NOT NULL REFERENCES knowledge_documents(id),
 ordinal INTEGER NOT NULL,
 content TEXT NOT NULL,
 locator TEXT NOT NULL,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(document_id,ordinal)
);
CREATE TABLE memory_items(
 id TEXT PRIMARY KEY,
 owner_id TEXT NOT NULL REFERENCES users(id),
 content TEXT NOT NULL,
 source_ref TEXT NOT NULL,
 revision INTEGER NOT NULL DEFAULT 1,
 status TEXT NOT NULL DEFAULT 'proposed',
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE changes(
 id TEXT PRIMARY KEY,
 affair_id TEXT NOT NULL REFERENCES affairs(id),
 notice_id TEXT NOT NULL REFERENCES notices(id),
 diff_json TEXT NOT NULL,
 plan_id TEXT REFERENCES plans(id),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE audit_logs(
 id TEXT PRIMARY KEY,
 actor_id TEXT REFERENCES users(id),
 action TEXT NOT NULL,
 target_ref TEXT NOT NULL,
 request_id TEXT NOT NULL,
 summary TEXT,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX ix_events_due ON events(owner_id,status,due_at);
CREATE INDEX ix_reminders_due ON reminders(status,fire_at);
CREATE INDEX ix_executions_claim ON executions(status,lease_until);
CREATE INDEX ix_notices_owner ON notices(owner_id,status);
