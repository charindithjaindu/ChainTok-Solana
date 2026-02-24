import { createHash } from "crypto";
import type {
  HeliusTransaction,
  ChainTokEvent,
  ProfileCreatedEvent,
  PostCreatedEvent,
  PostDeletedEvent,
  PostLikedEvent,
  PostUnlikedEvent,
  CommentCreatedEvent,
} from "./types";
import { PROGRAM_ID } from "./types";

// ─── Anchor Event Discriminators ────────────────────────────────────
// Anchor emits events as `Program data: <base64>` log lines.
// First 8 bytes = sha256("event:<EventName>")[0..8]

function eventDiscriminator(name: string): Buffer {
  return createHash("sha256")
    .update(`event:${name}`)
    .digest()
    .subarray(0, 8);
}

const DISC = {
  ProfileCreated: eventDiscriminator("ProfileCreated"),
  PostCreated: eventDiscriminator("PostCreated"),
  PostDeleted: eventDiscriminator("PostDeleted"),
  PostLiked: eventDiscriminator("PostLiked"),
  PostUnliked: eventDiscriminator("PostUnliked"),
  CommentCreated: eventDiscriminator("CommentCreated"),
} as const;

// ─── Borsh Decoding Helpers ─────────────────────────────────────────

function readPubkey(buf: Buffer, offset: number): [string, number] {
  // Pubkey = 32 bytes, encode as base58
  const bytes = buf.subarray(offset, offset + 32);
  return [encodeBase58(bytes), offset + 32];
}

function readString(buf: Buffer, offset: number): [string, number] {
  // Borsh string = 4-byte LE length + UTF-8 bytes
  const len = buf.readUInt32LE(offset);
  const str = buf.toString("utf-8", offset + 4, offset + 4 + len);
  return [str, offset + 4 + len];
}

function readI64(buf: Buffer, offset: number): [number, number] {
  // i64 little-endian (safe for values < 2^53)
  const lo = buf.readUInt32LE(offset);
  const hi = buf.readInt32LE(offset + 4);
  return [hi * 0x100000000 + lo, offset + 8];
}

function readU64(buf: Buffer, offset: number): [number, number] {
  const lo = buf.readUInt32LE(offset);
  const hi = buf.readUInt32LE(offset + 4);
  return [hi * 0x100000000 + lo, offset + 8];
}

// ─── Base58 Encoding ────────────────────────────────────────────────
const BASE58_CHARS =
  "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

function encodeBase58(bytes: Uint8Array): string {
  // Count leading zeros
  let zeroes = 0;
  for (const b of bytes) {
    if (b === 0) zeroes++;
    else break;
  }

  // Convert to base58
  const size = Math.ceil(bytes.length * 138 / 100) + 1;
  const b58 = new Uint8Array(size);
  let length = 0;

  for (const byte of bytes) {
    let carry = byte;
    let i = 0;
    for (let j = size - 1; (carry !== 0 || i < length) && j >= 0; j--, i++) {
      carry += 256 * b58[j];
      b58[j] = carry % 58;
      carry = Math.floor(carry / 58);
    }
    length = i;
  }

  let result = "1".repeat(zeroes);
  let skipZero = true;
  for (const digit of b58) {
    if (skipZero && digit === 0) continue;
    skipZero = false;
    result += BASE58_CHARS[digit];
  }

  return result || "1";
}

// ─── Event Parsers ──────────────────────────────────────────────────

function parseProfileCreated(buf: Buffer, off: number): ProfileCreatedEvent {
  let profilePubkey: string, authority: string;
  [profilePubkey, off] = readPubkey(buf, off);
  [authority, off] = readPubkey(buf, off);
  return { type: "ProfileCreated", profilePubkey, authority };
}

function parsePostCreated(buf: Buffer, off: number): PostCreatedEvent {
  let postPubkey: string,
    creator: string,
    arweaveUri: string,
    caption: string,
    timestamp: number;
  [postPubkey, off] = readPubkey(buf, off);
  [creator, off] = readPubkey(buf, off);
  [arweaveUri, off] = readString(buf, off);
  [caption, off] = readString(buf, off);
  [timestamp, off] = readI64(buf, off);
  return { type: "PostCreated", postPubkey, creator, arweaveUri, caption, timestamp };
}

function parsePostDeleted(buf: Buffer, off: number): PostDeletedEvent {
  let postPubkey: string, creator: string;
  [postPubkey, off] = readPubkey(buf, off);
  [creator, off] = readPubkey(buf, off);
  return { type: "PostDeleted", postPubkey, creator };
}

function parsePostLiked(buf: Buffer, off: number): PostLikedEvent {
  let postPubkey: string, liker: string, newLikeCount: number;
  [postPubkey, off] = readPubkey(buf, off);
  [liker, off] = readPubkey(buf, off);
  [newLikeCount, off] = readU64(buf, off);
  return { type: "PostLiked", postPubkey, liker, newLikeCount };
}

function parsePostUnliked(buf: Buffer, off: number): PostUnlikedEvent {
  let postPubkey: string, liker: string, newLikeCount: number;
  [postPubkey, off] = readPubkey(buf, off);
  [liker, off] = readPubkey(buf, off);
  [newLikeCount, off] = readU64(buf, off);
  return { type: "PostUnliked", postPubkey, liker, newLikeCount };
}

function parseCommentCreated(buf: Buffer, off: number): CommentCreatedEvent {
  let commentPubkey: string,
    postPubkey: string,
    author: string,
    content: string,
    timestamp: number;
  [commentPubkey, off] = readPubkey(buf, off);
  [postPubkey, off] = readPubkey(buf, off);
  [author, off] = readPubkey(buf, off);
  [content, off] = readString(buf, off);
  [timestamp, off] = readI64(buf, off);
  return { type: "CommentCreated", commentPubkey, postPubkey, author, content, timestamp };
}

// ─── Main Parser ────────────────────────────────────────────────────

const PROGRAM_DATA_PREFIX = "Program data: ";

/**
 * Parse an array of Helius enriched transactions into ChainTok events.
 * Decodes Anchor events from `Program data:` log entries.
 */
export function parseWebhookEvents(
  txs: HeliusTransaction[]
): ChainTokEvent[] {
  const events: ChainTokEvent[] = [];

  for (const tx of txs) {
    const logs = tx.logMessages ?? [];

    // Only process if our program was invoked
    const involvesProgram = logs.some((log) => log.includes(PROGRAM_ID));
    if (!involvesProgram) continue;

    for (const log of logs) {
      if (!log.startsWith(PROGRAM_DATA_PREFIX)) continue;

      const b64 = log.slice(PROGRAM_DATA_PREFIX.length);
      let buf: Buffer;
      try {
        buf = Buffer.from(b64, "base64");
      } catch {
        continue;
      }

      if (buf.length < 8) continue;

      const disc = buf.subarray(0, 8);
      const dataOffset = 8;

      try {
        if (disc.equals(DISC.ProfileCreated)) {
          events.push(parseProfileCreated(buf, dataOffset));
        } else if (disc.equals(DISC.PostCreated)) {
          events.push(parsePostCreated(buf, dataOffset));
        } else if (disc.equals(DISC.PostDeleted)) {
          events.push(parsePostDeleted(buf, dataOffset));
        } else if (disc.equals(DISC.PostLiked)) {
          events.push(parsePostLiked(buf, dataOffset));
        } else if (disc.equals(DISC.PostUnliked)) {
          events.push(parsePostUnliked(buf, dataOffset));
        } else if (disc.equals(DISC.CommentCreated)) {
          events.push(parseCommentCreated(buf, dataOffset));
        }
      } catch (err) {
        console.warn("[Webhook] Failed to decode event:", err);
      }
    }
  }

  return events;
}
