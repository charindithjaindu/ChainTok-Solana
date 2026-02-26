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
    updated_at    INTEGER NOT NULL,
    is_deleted    INTEGER DEFAULT 0
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

db.run(`
  CREATE TABLE IF NOT EXISTS likes (
    post_pubkey TEXT NOT NULL,
    liker       TEXT NOT NULL,
    timestamp   INTEGER NOT NULL,
    PRIMARY KEY (post_pubkey, liker)
  )
`);
db.run("CREATE INDEX IF NOT EXISTS idx_likes_liker ON likes(liker)");

db.run(`
  CREATE TABLE IF NOT EXISTS follows (
    follower  TEXT NOT NULL,
    following TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    PRIMARY KEY (follower, following)
  )
`);
db.run("CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower)");
db.run("CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following)");

db.run(`
  CREATE TABLE IF NOT EXISTS tips (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    sender      TEXT NOT NULL,
    receiver    TEXT NOT NULL,
    amount_sol  REAL NOT NULL,
    post_pubkey TEXT,
    signature   TEXT,
    timestamp   INTEGER NOT NULL
  )
`);
db.run("CREATE INDEX IF NOT EXISTS idx_tips_receiver ON tips(receiver)");

// Migrate existing DBs: add new columns if missing
for (const col of ['display_name', 'bio', 'pfp_uri']) {
  try {
    db.run(`ALTER TABLE profiles ADD COLUMN ${col} TEXT NOT NULL DEFAULT ''`);
  } catch (_) {}
}
try {
  db.run(`ALTER TABLE posts ADD COLUMN is_deleted INTEGER DEFAULT 0`);
} catch (_) {}

console.log("Database initialized at ./data/chainTok.db");

// ─── Prepared Statements ────────────────────────────────────────────

// Posts
const insertPostStmt = db.prepare(`
  INSERT OR IGNORE INTO posts (pubkey, creator, arweave_uri, caption, like_count, comment_count, timestamp, updated_at, is_deleted)
  VALUES ($pubkey, $creator, $arweave_uri, $caption, 0, 0, $timestamp, $updated_at, 0)
`);

const deletePostStmt = db.prepare(`
  UPDATE posts SET is_deleted = 1, updated_at = $updated_at
  WHERE pubkey = $pubkey
`);

const setLikeCountStmt = db.prepare(`
  UPDATE posts SET like_count = $like_count, updated_at = $updated_at WHERE pubkey = $pubkey
`);

const incrementCommentCountStmt = db.prepare(`
  UPDATE posts SET comment_count = comment_count + 1, updated_at = $updated_at WHERE pubkey = $pubkey
`);

const feedLatestStmt = db.prepare(
  "SELECT * FROM posts WHERE is_deleted = 0 ORDER BY timestamp DESC LIMIT $limit OFFSET $offset"
);

const feedHotStmt = db.prepare(
  "SELECT * FROM posts WHERE is_deleted = 0 ORDER BY like_count DESC, timestamp DESC LIMIT $limit OFFSET $offset"
);

const feedForYouStmt = db.prepare(`
  SELECT *,
    (like_count * 2 + comment_count * 3 + MAX(0, 100 - (CAST(strftime('%s','now') AS INTEGER) - timestamp) / 3600)) AS score,
    ABS(RANDOM()) % 100 AS rand
  FROM posts
  WHERE is_deleted = 0
  ORDER BY score DESC, rand DESC
  LIMIT $limit OFFSET $offset
`);

const getPostStmt = db.prepare("SELECT * FROM posts WHERE pubkey = $pubkey");

const getPostsByCreatorStmt = db.prepare(
  "SELECT * FROM posts WHERE creator = $creator AND is_deleted = 0 ORDER BY timestamp DESC LIMIT $limit OFFSET $offset"
);

const feedFollowingStmt = db.prepare(`
  SELECT p.* FROM posts p
  INNER JOIN follows f ON f.following = p.creator
  WHERE f.follower = $follower AND p.is_deleted = 0
  ORDER BY p.timestamp DESC
  LIMIT $limit OFFSET $offset
`);

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

// Likes
const insertLikeStmt = db.prepare(`
  INSERT OR IGNORE INTO likes (post_pubkey, liker, timestamp)
  VALUES ($post_pubkey, $liker, $timestamp)
`);

const deleteLikeStmt = db.prepare(`
  DELETE FROM likes WHERE post_pubkey = $post_pubkey AND liker = $liker
`);

const checkLikeStmt = db.prepare(
  "SELECT 1 FROM likes WHERE post_pubkey = $post_pubkey AND liker = $liker LIMIT 1"
);

// Follows
const insertFollowStmt = db.prepare(`
  INSERT OR IGNORE INTO follows (follower, following, timestamp)
  VALUES ($follower, $following, $timestamp)
`);

const deleteFollowStmt = db.prepare(`
  DELETE FROM follows WHERE follower = $follower AND following = $following
`);

const checkFollowStmt = db.prepare(
  "SELECT 1 FROM follows WHERE follower = $follower AND following = $following LIMIT 1"
);

const getFollowerCountStmt = db.prepare(
  "SELECT COUNT(*) as count FROM follows WHERE following = $following"
);

const getFollowingCountStmt = db.prepare(
  "SELECT COUNT(*) as count FROM follows WHERE follower = $follower"
);

const getFollowersStmt = db.prepare(
  "SELECT follower, timestamp FROM follows WHERE following = $following ORDER BY timestamp DESC LIMIT $limit OFFSET $offset"
);

const getFollowingListStmt = db.prepare(
  "SELECT following, timestamp FROM follows WHERE follower = $follower ORDER BY timestamp DESC LIMIT $limit OFFSET $offset"
);

// Tips
const insertTipStmt = db.prepare(`
  INSERT INTO tips (sender, receiver, amount_sol, post_pubkey, signature, timestamp)
  VALUES ($sender, $receiver, $amount_sol, $post_pubkey, $signature, $timestamp)
`);

const getTipsForUserStmt = db.prepare(
  "SELECT * FROM tips WHERE receiver = $receiver ORDER BY timestamp DESC LIMIT $limit OFFSET $offset"
);

const getTotalTipsStmt = db.prepare(
  "SELECT COALESCE(SUM(amount_sol), 0) as total FROM tips WHERE receiver = $receiver"
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
  sort: "latest" | "hot" | "foryou",
  limit: number,
  offset: number
): Post[] {
  if (sort === "foryou") {
    return feedForYouStmt.all({ $limit: limit, $offset: offset }) as Post[];
  }
  const stmt = sort === "hot" ? feedHotStmt : feedLatestStmt;
  return stmt.all({ $limit: limit, $offset: offset }) as Post[];
}

export function getFollowingFeed(
  follower: string,
  limit: number,
  offset: number
): Post[] {
  return feedFollowingStmt.all({
    $follower: follower,
    $limit: limit,
    $offset: offset,
  }) as Post[];
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

// ── Likes ────────────────────────────────────────────────────────────

export function recordLike(postPubkey: string, liker: string): void {
  const now = Math.floor(Date.now() / 1000);
  insertLikeStmt.run({ $post_pubkey: postPubkey, $liker: liker, $timestamp: now });
}

export function removeLike(postPubkey: string, liker: string): void {
  deleteLikeStmt.run({ $post_pubkey: postPubkey, $liker: liker });
}

export function isLikedBy(postPubkey: string, liker: string): boolean {
  return checkLikeStmt.get({ $post_pubkey: postPubkey, $liker: liker }) != null;
}

export function getLikedPostPubkeys(postPubkeys: string[], liker: string): Set<string> {
  if (postPubkeys.length === 0) return new Set();
  const placeholders = postPubkeys.map(() => '?').join(',');
  const results = db.prepare(
    `SELECT post_pubkey FROM likes WHERE liker = ? AND post_pubkey IN (${placeholders})`
  ).all(liker, ...postPubkeys) as { post_pubkey: string }[];
  return new Set(results.map(r => r.post_pubkey));
}

// ── Follows ─────────────────────────────────────────────────────────

export function followUser(follower: string, following: string): void {
  const now = Math.floor(Date.now() / 1000);
  insertFollowStmt.run({ $follower: follower, $following: following, $timestamp: now });
}

export function unfollowUser(follower: string, following: string): void {
  deleteFollowStmt.run({ $follower: follower, $following: following });
}

export function isFollowingUser(follower: string, following: string): boolean {
  return checkFollowStmt.get({ $follower: follower, $following: following }) != null;
}

export function getFollowerCount(authority: string): number {
  const result = getFollowerCountStmt.get({ $following: authority }) as { count: number };
  return result?.count ?? 0;
}

export function getFollowingCount(authority: string): number {
  const result = getFollowingCountStmt.get({ $follower: authority }) as { count: number };
  return result?.count ?? 0;
}

export function getFollowers(authority: string, limit: number, offset: number): { follower: string; timestamp: number }[] {
  return getFollowersStmt.all({ $following: authority, $limit: limit, $offset: offset }) as any[];
}

export function getFollowingList(authority: string, limit: number, offset: number): { following: string; timestamp: number }[] {
  return getFollowingListStmt.all({ $follower: authority, $limit: limit, $offset: offset }) as any[];
}

// ── Tips ─────────────────────────────────────────────────────────────

export function recordTip(tip: {
  sender: string;
  receiver: string;
  amountSol: number;
  postPubkey?: string;
  signature?: string;
}): void {
  const now = Math.floor(Date.now() / 1000);
  insertTipStmt.run({
    $sender: tip.sender,
    $receiver: tip.receiver,
    $amount_sol: tip.amountSol,
    $post_pubkey: tip.postPubkey ?? null,
    $signature: tip.signature ?? null,
    $timestamp: now,
  });
}

export function getTipsForUser(receiver: string, limit: number, offset: number) {
  return getTipsForUserStmt.all({ $receiver: receiver, $limit: limit, $offset: offset });
}

export function getTotalTips(receiver: string): number {
  const result = getTotalTipsStmt.get({ $receiver: receiver }) as { total: number };
  return result?.total ?? 0;
}

export default db;
