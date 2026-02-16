import { Database } from "bun:sqlite";
import { mkdirSync, existsSync } from "fs";
import type { Post } from "./types";

// ─── Ensure data directory exists ───────────────────────────────────
const DATA_DIR = "./data";
if (!existsSync(DATA_DIR)) {
    mkdirSync(DATA_DIR, { recursive: true });
}

// ─── Initialize SQLite ─────────────────────────────────────────────
const db = new Database(`${DATA_DIR}/chainTok.db`, { create: true });

// Enable WAL mode for better concurrent read performance
db.run("PRAGMA journal_mode = WAL");

// ─── Create Schema ─────────────────────────────────────────────────
db.run(`
  CREATE TABLE IF NOT EXISTS posts (
    pubkey        TEXT PRIMARY KEY,
    creator       TEXT NOT NULL,
    arweave_uri   TEXT NOT NULL,
    caption       TEXT,
    like_count    INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    timestamp     INTEGER NOT NULL,
    updated_at    INTEGER NOT NULL
  )
`);

db.run("CREATE INDEX IF NOT EXISTS idx_timestamp ON posts(timestamp)");
db.run("CREATE INDEX IF NOT EXISTS idx_like_count ON posts(like_count)");

console.log("✅ Database initialized at ./data/chainTok.db");

// ─── Prepared Statements ────────────────────────────────────────────
const insertPostStmt = db.prepare(`
  INSERT OR IGNORE INTO posts (pubkey, creator, arweave_uri, caption, like_count, comment_count, timestamp, updated_at)
  VALUES ($pubkey, $creator, $arweave_uri, $caption, 0, 0, $timestamp, $updated_at)
`);

const incrementLikeStmt = db.prepare(`
  UPDATE posts SET like_count = like_count + 1, updated_at = $updated_at WHERE pubkey = $pubkey
`);

const feedLatestStmt = db.prepare(`
  SELECT * FROM posts ORDER BY timestamp DESC LIMIT $limit OFFSET $offset
`);

const feedHotStmt = db.prepare(`
  SELECT * FROM posts ORDER BY like_count DESC, timestamp DESC LIMIT $limit OFFSET $offset
`);

const getPostStmt = db.prepare(`
  SELECT * FROM posts WHERE pubkey = $pubkey
`);

// ─── Exported Helpers ───────────────────────────────────────────────

export function upsertPost(post: {
    pubkey: string;
    creator: string;
    arweave_uri: string;
    caption: string;
    timestamp: number;
}): void {
    const now = Math.floor(Date.now() / 1000);
    insertPostStmt.run({
        $pubkey: post.pubkey,
        $creator: post.creator,
        $arweave_uri: post.arweave_uri,
        $caption: post.caption,
        $timestamp: post.timestamp,
        $updated_at: now,
    });
}

export function incrementLike(postPubkey: string): void {
    const now = Math.floor(Date.now() / 1000);
    incrementLikeStmt.run({
        $pubkey: postPubkey,
        $updated_at: now,
    });
}

export function getFeed(
    sort: "latest" | "hot",
    limit: number,
    offset: number
): Post[] {
    const stmt = sort === "hot" ? feedHotStmt : feedLatestStmt;
    return stmt.all({ $limit: limit, $offset: offset }) as Post[];
}

export function getPost(pubkey: string): Post | null {
    return (getPostStmt.get({ $pubkey: pubkey }) as Post) ?? null;
}

export default db;
