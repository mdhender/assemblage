-- Copyright (c) 2026 Michael D Henderson.
--
-- 0001: the complete initial schema.
--
-- This is the alpha baseline. Schema changes are folded into this migration
-- until the migration history is declared stable.

CREATE TABLE users (
    id            INTEGER PRIMARY KEY,
    uid           TEXT    NOT NULL UNIQUE,
    email         TEXT    NOT NULL UNIQUE,
    name          TEXT    NOT NULL,
    active        INTEGER NOT NULL DEFAULT 1,
    created_at    TEXT    NOT NULL,
    password_hash TEXT    NOT NULL DEFAULT ''
) STRICT;

CREATE TABLE events (
    id           INTEGER PRIMARY KEY,
    type         TEXT    NOT NULL,
    actor_id     INTEGER          REFERENCES users(id),
    subject_kind TEXT    NOT NULL,
    subject_id   INTEGER NOT NULL,
    payload      TEXT    NOT NULL DEFAULT '{}',
    occurred_at  TEXT    NOT NULL
) STRICT;

CREATE INDEX events_subject ON events(subject_kind, subject_id, id DESC);
CREATE INDEX events_type ON events(type, occurred_at);

CREATE TABLE roles (
    id   INTEGER PRIMARY KEY,
    slug TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL
) STRICT;

CREATE TABLE user_roles (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
) STRICT;

CREATE INDEX user_roles_role ON user_roles(role_id);

CREATE TABLE sites (
    id     INTEGER PRIMARY KEY,
    uid    TEXT    NOT NULL UNIQUE,
    name   TEXT    NOT NULL,
    domain TEXT    NOT NULL,
    active INTEGER NOT NULL DEFAULT 1
) STRICT;

CREATE UNIQUE INDEX sites_domain ON sites(domain);

CREATE TABLE sessions (
    id           INTEGER PRIMARY KEY,
    user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_sha256 TEXT    NOT NULL UNIQUE,
    created_at   TEXT    NOT NULL,
    expires_at   TEXT    NOT NULL,
    last_seen_at TEXT    NOT NULL
) STRICT;

CREATE INDEX sessions_user ON sessions(user_id);
CREATE INDEX sessions_expiry ON sessions(expires_at);

CREATE TABLE element_types (
    id         INTEGER PRIMARY KEY,
    uid        TEXT    NOT NULL UNIQUE,
    key_name   TEXT    NOT NULL UNIQUE,
    name       TEXT    NOT NULL,
    kind       TEXT    NOT NULL,
    top_level  INTEGER NOT NULL DEFAULT 0,
    fixed_uri  INTEGER NOT NULL DEFAULT 0,
    paginated  INTEGER NOT NULL DEFAULT 0,
    schema     TEXT    NOT NULL,
    created_at TEXT    NOT NULL
) STRICT;

CREATE TABLE workflows (
    id            INTEGER PRIMARY KEY,
    uid           TEXT NOT NULL UNIQUE,
    site_id       INTEGER  REFERENCES sites(id),
    kind          TEXT NOT NULL,
    name          TEXT NOT NULL,
    initial_state TEXT NOT NULL
) STRICT;

CREATE UNIQUE INDEX workflows_default_per_kind
    ON workflows(kind) WHERE site_id IS NULL;
CREATE UNIQUE INDEX workflows_site_per_kind
    ON workflows(kind, site_id) WHERE site_id IS NOT NULL;

CREATE TABLE workflow_states (
    workflow_id        INTEGER NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
    slug               TEXT    NOT NULL,
    name               TEXT    NOT NULL,
    position           INTEGER NOT NULL,
    publishable        INTEGER NOT NULL DEFAULT 0,
    terminal           INTEGER NOT NULL DEFAULT 0,
    required_approvals INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (workflow_id, slug)
) STRICT;

CREATE TABLE workflow_transitions (
    id          INTEGER PRIMARY KEY,
    workflow_id INTEGER NOT NULL,
    from_state  TEXT    NOT NULL,
    to_state    TEXT    NOT NULL,
    name        TEXT    NOT NULL,
    privilege   INTEGER NOT NULL,
    guards      TEXT    NOT NULL DEFAULT '[]',
    effects     TEXT    NOT NULL DEFAULT '{}',
    position    INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (workflow_id, from_state) REFERENCES workflow_states(workflow_id, slug),
    FOREIGN KEY (workflow_id, to_state) REFERENCES workflow_states(workflow_id, slug),
    UNIQUE (workflow_id, from_state, to_state)
) STRICT;

CREATE TABLE documents (
    id                 INTEGER PRIMARY KEY,
    uid                TEXT    NOT NULL UNIQUE,
    site_id            INTEGER NOT NULL REFERENCES sites(id),
    kind               TEXT    NOT NULL,
    element_type_id    INTEGER NOT NULL REFERENCES element_types(id),
    workflow_id        INTEGER NOT NULL REFERENCES workflows(id),
    state              TEXT    NOT NULL,
    assigned_to        INTEGER          REFERENCES users(id),
    due_at             TEXT,
    locked_by          INTEGER          REFERENCES users(id),
    lock_expires_at    TEXT,
    current_version_id INTEGER          REFERENCES document_versions(id),
    live_version_id    INTEGER          REFERENCES document_versions(id),
    created_at         TEXT    NOT NULL,
    updated_at         TEXT    NOT NULL,
    FOREIGN KEY (workflow_id, state) REFERENCES workflow_states(workflow_id, slug)
) STRICT;

CREATE INDEX documents_queue ON documents(workflow_id, state, due_at);
CREATE INDEX documents_overdue ON documents(due_at) WHERE due_at IS NOT NULL;
CREATE INDEX documents_live ON documents(live_version_id) WHERE live_version_id IS NOT NULL;
CREATE INDEX documents_assignee ON documents(assigned_to, state, due_at);
CREATE INDEX documents_state ON documents(state, due_at);
CREATE INDEX documents_site ON documents(site_id, state, due_at);

CREATE TABLE document_versions (
    id            INTEGER PRIMARY KEY,
    document_id   INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    version       INTEGER NOT NULL,
    title         TEXT    NOT NULL,
    slug          TEXT    NOT NULL DEFAULT '',
    cover_date    TEXT,
    content       TEXT    NOT NULL DEFAULT '{}',
    note          TEXT,
    created_by    INTEGER NOT NULL REFERENCES users(id),
    created_at    TEXT    NOT NULL,
    checked_in_at TEXT,
    UNIQUE (document_id, version)
) STRICT;

CREATE UNIQUE INDEX document_versions_one_draft
    ON document_versions(document_id) WHERE checked_in_at IS NULL;

CREATE TRIGGER document_versions_immutable
BEFORE UPDATE ON document_versions
WHEN OLD.checked_in_at IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'checked-in versions are immutable');
END;

CREATE TABLE approvals (
    id          INTEGER PRIMARY KEY,
    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    version_id  INTEGER NOT NULL REFERENCES document_versions(id) ON DELETE CASCADE,
    state       TEXT    NOT NULL,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    created_at  TEXT    NOT NULL,
    UNIQUE (version_id, state, user_id)
) STRICT;

CREATE INDEX approvals_version ON approvals(version_id, state);

CREATE TABLE comments (
    id          INTEGER PRIMARY KEY,
    uid         TEXT    NOT NULL UNIQUE,
    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    version_id  INTEGER          REFERENCES document_versions(id),
    in_reply_to INTEGER          REFERENCES comments(id),
    author_id   INTEGER NOT NULL REFERENCES users(id),
    body        TEXT    NOT NULL,
    resolved_at TEXT,
    resolved_by INTEGER          REFERENCES users(id),
    created_at  TEXT    NOT NULL
) STRICT;

CREATE INDEX comments_open ON comments(document_id) WHERE resolved_at IS NULL;
CREATE INDEX comments_document ON comments(document_id, id);

CREATE TABLE jobs (
    id               INTEGER PRIMARY KEY,
    uid              TEXT    NOT NULL UNIQUE,
    kind             TEXT    NOT NULL,
    priority         INTEGER NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
    scheduled_for    TEXT    NOT NULL,
    payload          TEXT    NOT NULL,
    lease_owner      TEXT,
    lease_expires_at TEXT,
    attempts         INTEGER NOT NULL DEFAULT 0,
    max_attempts     INTEGER NOT NULL DEFAULT 5,
    last_error       TEXT,
    completed_at     TEXT,
    failed_at        TEXT,
    created_by       INTEGER          REFERENCES users(id),
    created_at       TEXT    NOT NULL
) STRICT;

CREATE INDEX jobs_claimable ON jobs(priority, scheduled_for, id)
    WHERE completed_at IS NULL AND failed_at IS NULL;
CREATE INDEX jobs_leased ON jobs(lease_expires_at)
    WHERE lease_expires_at IS NOT NULL AND completed_at IS NULL AND failed_at IS NULL;
CREATE INDEX jobs_failed ON jobs(failed_at) WHERE failed_at IS NOT NULL;

CREATE TABLE categories (
    id        INTEGER PRIMARY KEY,
    uid       TEXT    NOT NULL UNIQUE,
    site_id   INTEGER NOT NULL REFERENCES sites(id),
    parent_id INTEGER          REFERENCES categories(id),
    directory TEXT    NOT NULL,
    path      TEXT    NOT NULL,
    name      TEXT    NOT NULL,
    UNIQUE (site_id, path)
) STRICT;

CREATE INDEX categories_parent ON categories(parent_id) WHERE parent_id IS NOT NULL;

CREATE TABLE document_categories (
    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    category_id INTEGER NOT NULL REFERENCES categories(id),
    primary_cat INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (document_id, category_id)
) STRICT;

CREATE UNIQUE INDEX document_categories_one_primary
    ON document_categories(document_id) WHERE primary_cat = 1;
CREATE INDEX document_categories_category ON document_categories(category_id);

CREATE TABLE output_channels (
    id               INTEGER PRIMARY KEY,
    uid              TEXT    NOT NULL UNIQUE,
    site_id          INTEGER NOT NULL REFERENCES sites(id),
    name             TEXT    NOT NULL,
    protocol         TEXT    NOT NULL DEFAULT 'https://',
    filename         TEXT    NOT NULL DEFAULT 'index',
    file_ext         TEXT    NOT NULL DEFAULT 'html',
    uri_format       TEXT    NOT NULL,
    fixed_uri_format TEXT    NOT NULL,
    use_slug         INTEGER NOT NULL DEFAULT 0,
    uri_case         TEXT    NOT NULL DEFAULT 'mixed'
        CHECK (uri_case IN ('mixed', 'lower', 'upper')),
    UNIQUE (site_id, name)
) STRICT;

CREATE TABLE collections (
    id   INTEGER PRIMARY KEY,
    uid  TEXT NOT NULL UNIQUE,
    slug TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL
) STRICT;

CREATE TABLE document_collections (
    document_id   INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    PRIMARY KEY (document_id, collection_id)
) STRICT;

CREATE TABLE grants (
    id            INTEGER PRIMARY KEY,
    role_id       INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    privilege     INTEGER NOT NULL,
    site_id       INTEGER          REFERENCES sites(id),
    doc_kind      TEXT,
    state         TEXT,
    created_at    TEXT    NOT NULL,
    created_by    INTEGER          REFERENCES users(id),
    document_id   INTEGER          REFERENCES documents(id),
    workflow_id   INTEGER          REFERENCES workflows(id),
    category_id   INTEGER          REFERENCES categories(id),
    category_deep INTEGER NOT NULL DEFAULT 1,
    collection_id INTEGER          REFERENCES collections(id)
) STRICT;

CREATE INDEX grants_role ON grants(role_id);

CREATE TABLE published_resources (
    id                INTEGER PRIMARY KEY,
    document_id       INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    output_channel_id INTEGER NOT NULL REFERENCES output_channels(id),
    version_id        INTEGER NOT NULL REFERENCES document_versions(id),
    uri               TEXT    NOT NULL,
    path              TEXT    NOT NULL,
    checksum          TEXT    NOT NULL,
    bytes             INTEGER NOT NULL,
    published_at      TEXT    NOT NULL,
    UNIQUE (output_channel_id, uri)
) STRICT;

CREATE INDEX published_resources_document
    ON published_resources(document_id, output_channel_id);

CREATE TABLE alert_rules (
    id         INTEGER PRIMARY KEY,
    uid        TEXT    NOT NULL UNIQUE,
    name       TEXT    NOT NULL,
    event_type TEXT    NOT NULL,
    conditions TEXT    NOT NULL DEFAULT '[]',
    channel    TEXT    NOT NULL,
    target     TEXT    NOT NULL,
    active     INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
    created_by INTEGER          REFERENCES users(id),
    created_at TEXT    NOT NULL,
    updated_at TEXT    NOT NULL
) STRICT;

CREATE INDEX alert_rules_event ON alert_rules(event_type) WHERE active = 1;

CREATE TABLE notifications (
    id         INTEGER PRIMARY KEY,
    uid        TEXT    NOT NULL UNIQUE,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_id   INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    rule_id    INTEGER          REFERENCES alert_rules(id) ON DELETE SET NULL,
    read_at    TEXT,
    created_at TEXT    NOT NULL
) STRICT;

CREATE UNIQUE INDEX notifications_once ON notifications(user_id, event_id, rule_id);
CREATE INDEX notifications_inbox ON notifications(user_id, id DESC);
CREATE INDEX notifications_unread ON notifications(user_id, id DESC) WHERE read_at IS NULL;

CREATE TABLE alert_cursor (
    id            INTEGER PRIMARY KEY CHECK (id = 1),
    last_event_id INTEGER NOT NULL,
    updated_at    TEXT    NOT NULL
) STRICT;

CREATE TABLE invitations (
    id           INTEGER PRIMARY KEY,
    uid          TEXT NOT NULL UNIQUE,
    email        TEXT NOT NULL,
    token_sha256 TEXT,
    status       TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'redeemed', 'revoked', 'superseded')),
    expires_at   TEXT NOT NULL,
    reason       TEXT,
    invited_by   INTEGER REFERENCES users(id),
    user_id      INTEGER REFERENCES users(id),
    created_at   TEXT NOT NULL,
    settled_at   TEXT
) STRICT;

CREATE UNIQUE INDEX invitations_one_pending ON invitations(email) WHERE status = 'pending';
CREATE INDEX invitations_token ON invitations(token_sha256) WHERE token_sha256 IS NOT NULL;
CREATE INDEX invitations_listing ON invitations(status, id DESC);

-- The default workflow is schema data because documents require a workflow and
-- a state before application seed data can be written.
INSERT INTO workflows(uid, site_id, kind, name, initial_state)
VALUES ('00000000000000000000000001', NULL, 'story', 'Story', 'draft');

INSERT INTO workflow_states
    (workflow_id, slug, name, position, publishable, terminal, required_approvals)
SELECT w.id, s.slug, s.name, s.position, s.publishable, s.terminal, s.required_approvals
FROM workflows w
JOIN (
    SELECT 'draft' AS slug, 'Draft' AS name, 1 AS position, 0 AS publishable, 0 AS terminal, 0 AS required_approvals
    UNION ALL SELECT 'review', 'In review', 2, 0, 0, 1
    UNION ALL SELECT 'approved', 'Approved', 3, 1, 0, 0
    UNION ALL SELECT 'published', 'Published', 4, 1, 0, 0
    UNION ALL SELECT 'archived', 'Archived', 5, 0, 1, 0
) s
WHERE w.uid = '00000000000000000000000001';

INSERT INTO workflow_transitions
    (workflow_id, from_state, to_state, name, privilege, guards, effects, position)
SELECT w.id, t.from_state, t.to_state, t.name, t.privilege, t.guards, t.effects, t.position
FROM workflows w
JOIN (
    SELECT 'draft' AS from_state, 'review' AS to_state, 'Submit' AS name, 2 AS privilege,
        '["not_locked","assignee_only","has_slug"]' AS guards,
        '{"clear_assignee":"","set_due_in":"48h"}' AS effects, 1 AS position
    UNION ALL SELECT 'review', 'approved', 'Approve', 4,
        '["approvals_met","comments_resolved"]', '{"clear_assignee":""}', 2
    UNION ALL SELECT 'approved', 'published', 'Publish', 5,
        '["not_locked","has_cover_date","has_checked_in_version"]', '{"publish":""}', 3
    UNION ALL SELECT 'review', 'draft', 'Reject', 4,
        '["note_required"]', '{"clear_approvals":""}', 4
    UNION ALL SELECT 'approved', 'draft', 'Revoke', 4,
        '["note_required"]', '{"clear_approvals":""}', 5
    UNION ALL SELECT 'published', 'draft', 'Revise', 3,
        '[]', '{"assign_to_actor":"","clear_approvals":""}', 6
    UNION ALL SELECT 'draft', 'archived', 'Archive', 4,
        '["not_locked"]', '{"clear_assignee":""}', 7
    UNION ALL SELECT 'review', 'archived', 'Archive', 4,
        '["not_locked"]', '{"clear_assignee":""}', 8
    UNION ALL SELECT 'published', 'archived', 'Archive', 4,
        '["not_locked"]', '{"clear_assignee":""}', 9
    UNION ALL SELECT 'archived', 'draft', 'Restore', 3, '[]', '{}', 10
) t
WHERE w.uid = '00000000000000000000000001';

-- New alert rules begin after the events that already exist at initialization.
INSERT INTO alert_cursor(id, last_event_id, updated_at)
VALUES (1, (SELECT COALESCE(MAX(id), 0) FROM events),
        strftime('%Y-%m-%dT%H:%M:%f', 'now') || 'Z');
