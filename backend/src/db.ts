import { Database } from "bun:sqlite";
import { mkdirSync, existsSync } from "fs";
import type { Post, Comment, Profile } from "./types";

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
db.run("CREATE INDEX IF NOT EXISTS idx_posts_timestamp ON posts(timestamp)");
db.run("CREATE INDEX IF NOT EXISTS idx_posts_like_count ON posts(like_count)");
db.run("CREATE INDEX IF NOT EXISTS idx_posts_creator ON posts(creator)");

db.run(`
  CREATE TABLE IF NOT EXISTS comments (
    pubkey      TEXT PRIMARY KEY,
    post_pubkey TEXT NOT NULL,
    author      TEXT NOT NULL,
    content     TEXT NOT NULL,
    timestamp   INTEGER NOT NULL,
    FOREIGN KEY (post_pubkey) REFERENCES posts(pubkey)
  )
`);
db.run(
  "CREATE INDEX IF NOT EXISTS idx_comments_post ON comments(post_pubkey)"
);

db.run(`
  CREATE TABLE IF NOT EXISTS profiles (
    pubkey       TEXT PRIMARY KEY,
    authority    TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL DEFAULT '',
    bio          TEXT NOT NULL DEFAULT '',
    pfp_uri      TEXT NOT NULL DEFAULT '',
    created_at   INTEGER NOT NULL
  )
`);

// Migrate existing DBs: add new columns if missing
for (const col of ['display_name', 'bio', 'pfp_uri']) {
  try {
    db.run(`ALTER TABLE profiles ADD COLUMN ${col} TEXT NOT NULL DEFAULT ''`);
  } catch (_) {
    // Column already exists
  }
}

console.log("✅ Database initialized at ./data/chainTok.db");

// ─── Prepared Statements ────────────────────────────────────────────

// Posts
const insertPostStmt = db.prepare(`
  INSERT OR IGNORE INTO posts (pubkey, creator, arweave_uri, caption, like_count, comment_count, timestamp, updated_at)
  VALUES ($pubkey, $creator, $arweave_uri, $caption, 0, 0, $timestamp, $updated_at)
`);

const deletePostStmt = db.prepare(`
  UPDATE posts SET like_count = 0, comment_count = 0, caption = '[deleted]', updated_at = $updated_at
  WHERE pubkey = $pubkey
`);

const setLikeCountStmt = db.prepare(`
  UPDATE posts SET like_count = $like_count, updated_at = $updated_at WHERE pubkey = $pubkey
`);

const incrementCommentCountStmt = db.prepare(`
  UPDATE posts SET comment_count = comment_count + 1, updated_at = $updated_at WHERE pubkey = $pubkey
`);

const feedLatestStmt = db.prepare(
  "SELECT * FROM posts ORDER BY timestamp DESC LIMIT $limit OFFSET $offset"
);

const feedHotStmt = db.prepare(
  "SELECT * FROM posts ORDER BY like_count DESC, timestamp DESC LIMIT $limit OFFSET $offset"
);

const getPostStmt = db.prepare("SELECT * FROM posts WHERE pubkey = $pubkey");

const getPostsByCreatorStmt = db.prepare(
  "SELECT * FROM posts WHERE creator = $creator ORDER BY timestamp DESC LIMIT $limit OFFSET $offset"
);

// Comments
const insertCommentStmt = db.prepare(`
  INSERT OR IGNORE INTO comments (pubkey, post_pubkey, author, content, timestamp)
  VALUES ($pubkey, $post_pubkey, $author, $content, $timestamp)
`);

const getCommentsStmt = db.prepare(
  "SELECT * FROM comments WHERE post_pubkey = $post_pubkey ORDER BY timestamp DESC LIMIT $limit OFFSET $offset"
);

// Profiles
const insertProfileStmt = db.prepare(`
  INSERT INTO profiles (pubkey, authority, display_name, bio, pfp_uri, created_at)
  VALUES ($pubkey, $authority, $display_name, $bio, $pfp_uri, $created_at)
  ON CONFLICT(pubkey) DO UPDATE SET
    display_name = CASE WHEN excluded.display_name != '' THEN excluded.display_name ELSE profiles.display_name END,
    bio = CASE WHEN excluded.bio != '' THEN excluded.bio ELSE profiles.bio END,
    pfp_uri = CASE WHEN excluded.pfp_uri != '' THEN excluded.pfp_uri ELSE profiles.pfp_uri END
`);

const updateProfileMetaStmt = db.prepare(`
  INSERT INTO profiles (pubkey, authority, display_name, bio, pfp_uri, created_at)
  VALUES ($pubkey, $authority, $display_name, $bio, $pfp_uri, $created_at)
  ON CONFLICT(authority) DO UPDATE SET
    display_name = $display_name,
    bio = $bio,
    pfp_uri = $pfp_uri
`);

const getProfileByAuthorityStmt = db.prepare(
  "SELECT * FROM profiles WHERE authority = $authority"
);

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

export function softDeletePost(pubkey: string): void {
  const now = Math.floor(Date.now() / 1000);
  deletePostStmt.run({ $pubkey: pubkey, $updated_at: now });
}

export function setLikeCount(postPubkey: string, likeCount: number): void {
  const now = Math.floor(Date.now() / 1000);
  setLikeCountStmt.run({
    $pubkey: postPubkey,
    $like_count: likeCount,
    $updated_at: now,
  });
}

export function incrementCommentCount(postPubkey: string): void {
  const now = Math.floor(Date.now() / 1000);
  incrementCommentCountStmt.run({ $pubkey: postPubkey, $updated_at: now });
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

export function getPostsByCreator(
  creator: string,
  limit: number,
  offset: number
): Post[] {
  return getPostsByCreatorStmt.all({
    $creator: creator,
    $limit: limit,
    $offset: offset,
  }) as Post[];
}

export function insertComment(comment: {
  pubkey: string;
  postPubkey: string;
  author: string;
  content: string;
  timestamp: number;
}): void {
  insertCommentStmt.run({
    $pubkey: comment.pubkey,
    $post_pubkey: comment.postPubkey,
    $author: comment.author,
    $content: comment.content,
    $timestamp: comment.timestamp,
  });
  incrementCommentCount(comment.postPubkey);
}

export function getComments(
  postPubkey: string,
  limit: number,
  offset: number
): Comment[] {
  return getCommentsStmt.all({
    $post_pubkey: postPubkey,
    $limit: limit,
    $offset: offset,
  }) as Comment[];
}

export function upsertProfile(profile: {
  pubkey: string;
  authority: string;
  display_name?: string;
  bio?: string;
  pfp_uri?: string;
}): void {
  const now = Math.floor(Date.now() / 1000);
  insertProfileStmt.run({
    $pubkey: profile.pubkey,
    $authority: profile.authority,
    $display_name: profile.display_name ?? '',
    $bio: profile.bio ?? '',
    $pfp_uri: profile.pfp_uri ?? '',
    $created_at: now,
  });
}

export function updateProfileMeta(authority: string, meta: {
  display_name: string;
  bio: string;
  pfp_uri: string;
}): void {
  const now = Math.floor(Date.now() / 1000);
  updateProfileMetaStmt.run({
    $pubkey: '',
    $authority: authority,
    $display_name: meta.display_name,
    $bio: meta.bio,
    $pfp_uri: meta.pfp_uri,
    $created_at: now,
  });
}

export function getProfileByAuthority(authority: string): Profile | null {
  return (
    (getProfileByAuthorityStmt.get({ $authority: authority }) as Profile) ??
    null
  );
}

export default db;
