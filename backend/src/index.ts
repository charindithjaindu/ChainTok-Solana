import { Elysia, t } from "elysia";
import { cors } from "@elysiajs/cors";
import { randomUUID } from "crypto";
import { mkdir, exists } from "fs/promises";
import path from "path";

import {
  upsertPost,
  softDeletePost,
  setLikeCount,
  insertComment,
  getFeed,
  getPost,
  getPostsByCreator,
  getComments,
  upsertProfile,
  getProfileByAuthority,
} from "./db";
import { parseWebhookEvents } from "./webhook";
import type { WebhookPayload } from "./types";
import { PROGRAM_ID } from "./types";

// ─── Constants ──────────────────────────────────────────────────────
const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3000;
const SOLANA_RPC = process.env.SOLANA_RPC ?? "https://api.devnet.solana.com";
const UPLOADS_DIR = path.resolve(import.meta.dir, "../data/uploads");

// Ensure uploads directory exists
await mkdir(UPLOADS_DIR, { recursive: true });

// ─── App ────────────────────────────────────────────────────────────
const app = new Elysia()
  // ── CORS (allow all for dev) ──
  .use(cors({ origin: "*" }))

  // ── Global error handler ──
  .onError(({ code, error, set }) => {
    console.error(`[Error] ${code}:`, String(error));

    if (code === "NOT_FOUND") {
      set.status = 404;
      return { error: "Not found" };
    }

    set.status = 500;
    return { error: "Internal server error" };
  })

  // ── Health Check ──
  .get("/", () => ({ status: "ok" }))

  // ── Helius Webhook Receiver ──
  .post(
    "/webhook",
    ({ body }) => {
      try {
        const txs = body as WebhookPayload;

        if (!Array.isArray(txs)) {
          return { error: "Expected array of transactions" };
        }

        const events = parseWebhookEvents(txs);
        let postsCreated = 0;
        let postsDeleted = 0;
        let likesProcessed = 0;
        let commentsCreated = 0;
        let profilesCreated = 0;

        for (const event of events) {
          switch (event.type) {
            case "ProfileCreated":
              upsertProfile({
                pubkey: event.profilePubkey,
                authority: event.authority,
              });
              profilesCreated++;
              break;

            case "PostCreated":
              upsertPost({
                pubkey: event.postPubkey,
                creator: event.creator,
                arweave_uri: event.arweaveUri,
                caption: event.caption,
                timestamp: event.timestamp,
              });
              postsCreated++;
              break;

            case "PostDeleted":
              softDeletePost(event.postPubkey);
              postsDeleted++;
              break;

            case "PostLiked":
              setLikeCount(event.postPubkey, event.newLikeCount);
              likesProcessed++;
              break;

            case "PostUnliked":
              setLikeCount(event.postPubkey, event.newLikeCount);
              likesProcessed++;
              break;

            case "CommentCreated":
              insertComment({
                pubkey: event.commentPubkey,
                postPubkey: event.postPubkey,
                author: event.author,
                content: event.content,
                timestamp: event.timestamp,
              });
              commentsCreated++;
              break;
          }
        }

        console.log(
          `[Webhook] ${events.length} events → +${postsCreated} posts, -${postsDeleted} deleted, ${likesProcessed} likes, +${commentsCreated} comments, +${profilesCreated} profiles`
        );

        return { ok: true, processed: events.length };
      } catch (err) {
        console.error("[Webhook] Error processing payload:", err);
        return { ok: false, error: "Failed to process webhook" };
      }
    },
    {
      detail: { description: "Helius webhook receiver" },
    }
  )

  // ── Feed Endpoint ──
  .get(
    "/feed",
    ({ query }) => {
      const sort =
        query.sort === "hot" ? ("hot" as const) : ("latest" as const);
      const limit = Math.min(Math.max(parseInt(query.limit ?? "20"), 1), 100);
      const offset = Math.max(parseInt(query.offset ?? "0"), 0);

      const posts = getFeed(sort, limit, offset);
      return posts;
    },
    {
      query: t.Object({
        sort: t.Optional(t.String()),
        limit: t.Optional(t.String()),
        offset: t.Optional(t.String()),
      }),
      detail: { description: "Get post feed" },
    }
  )

  // ── Single Post ──
  .get(
    "/post/:pubkey",
    ({ params, set }) => {
      const post = getPost(params.pubkey);
      if (!post) {
        set.status = 404;
        return { error: "Post not found" };
      }
      return post;
    },
    {
      params: t.Object({ pubkey: t.String() }),
      detail: { description: "Get single post by pubkey" },
    }
  )

  // ── Post Comments ──
  .get(
    "/post/:pubkey/comments",
    ({ params, query }) => {
      const limit = Math.min(Math.max(parseInt(query.limit ?? "50"), 1), 200);
      const offset = Math.max(parseInt(query.offset ?? "0"), 0);
      return getComments(params.pubkey, limit, offset);
    },
    {
      params: t.Object({ pubkey: t.String() }),
      query: t.Object({
        limit: t.Optional(t.String()),
        offset: t.Optional(t.String()),
      }),
      detail: { description: "Get comments for a post" },
    }
  )

  // ── User Posts ──
  .get(
    "/user/:pubkey/posts",
    ({ params, query }) => {
      const limit = Math.min(Math.max(parseInt(query.limit ?? "20"), 1), 100);
      const offset = Math.max(parseInt(query.offset ?? "0"), 0);
      return getPostsByCreator(params.pubkey, limit, offset);
    },
    {
      params: t.Object({ pubkey: t.String() }),
      query: t.Object({
        limit: t.Optional(t.String()),
        offset: t.Optional(t.String()),
      }),
      detail: { description: "Get posts by a specific creator" },
    }
  )

  // ── User Profile ──
  .get(
    "/user/:pubkey/profile",
    ({ params, set }) => {
      const profile = getProfileByAuthority(params.pubkey);
      if (!profile) {
        set.status = 404;
        return { error: "Profile not found" };
      }
      return profile;
    },
    {
      params: t.Object({ pubkey: t.String() }),
      detail: { description: "Get profile by wallet authority pubkey" },
    }
  )

  // ── Solana RPC Proxy (for emulator DNS workaround) ──
  .post(
    "/rpc",
    async ({ body }) => {
      try {
        const res = await fetch(SOLANA_RPC, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
        const data = await res.json();
        return data;
      } catch (err) {
        console.error("[RPC Proxy] Error:", err);
        return { error: "RPC proxy failed" };
      }
    },
    {
      detail: { description: "Solana RPC proxy for emulator DNS workaround" },
    }
  )

  // ── Sync: Poll devnet for recent program transactions (replaces Helius for dev) ──
  .post(
    "/sync",
    async () => {
      try {
        // 1. Get recent signatures for the program
        const sigsRes = await fetch(SOLANA_RPC, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            jsonrpc: "2.0",
            id: 1,
            method: "getSignaturesForAddress",
            params: [PROGRAM_ID, { limit: 50 }],
          }),
        });
        const sigsData = (await sigsRes.json()) as any;
        const signatures = sigsData.result ?? [];

        if (signatures.length === 0) {
          return { ok: true, message: "No transactions found", processed: 0 };
        }

        let totalEvents = 0;

        // 2. Fetch each transaction and parse logs
        for (const sigInfo of signatures) {
          const txRes = await fetch(SOLANA_RPC, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              jsonrpc: "2.0",
              id: 1,
              method: "getTransaction",
              params: [sigInfo.signature, { encoding: "json", maxSupportedTransactionVersion: 0 }],
            }),
          });
          const txData = (await txRes.json()) as any;
          const tx = txData.result;
          if (!tx || !tx.meta?.logMessages) continue;

          // Build a minimal HeliusTransaction-shaped object for our existing parser
          const fakeTx = {
            description: "",
            type: "UNKNOWN",
            source: "SYNC",
            signature: sigInfo.signature,
            slot: tx.slot,
            timestamp: tx.blockTime ?? Math.floor(Date.now() / 1000),
            nativeTransfers: [],
            tokenTransfers: [],
            accountData: [],
            instructions: [],
            events: {},
            logMessages: tx.meta.logMessages as string[],
          };

          const events = parseWebhookEvents([fakeTx]);

          for (const event of events) {
            switch (event.type) {
              case "ProfileCreated":
                upsertProfile({ pubkey: event.profilePubkey, authority: event.authority });
                break;
              case "PostCreated":
                upsertPost({ pubkey: event.postPubkey, creator: event.creator, arweave_uri: event.arweaveUri, caption: event.caption, timestamp: event.timestamp });
                break;
              case "PostDeleted":
                softDeletePost(event.postPubkey);
                break;
              case "PostLiked":
                setLikeCount(event.postPubkey, event.newLikeCount);
                break;
              case "PostUnliked":
                setLikeCount(event.postPubkey, event.newLikeCount);
                break;
              case "CommentCreated":
                insertComment({ pubkey: event.commentPubkey, postPubkey: event.postPubkey, author: event.author, content: event.content, timestamp: event.timestamp });
                break;
            }
          }

          totalEvents += events.length;
        }

        console.log(`[Sync] Processed ${signatures.length} txs → ${totalEvents} events`);
        return { ok: true, processed: totalEvents, txs: signatures.length };
      } catch (err) {
        console.error("[Sync] Error:", err);
        return { ok: false, error: "Sync failed" };
      }
    },
    {
      detail: { description: "Poll devnet for recent program transactions and index them" },
    }
  )

  // ── File Upload (video / media) ──
  .post(
    "/upload",
    async ({ body }) => {
      try {
        const file = (body as any).file;
        if (!file || !(file instanceof Blob)) {
          return { error: "No file provided" };
        }

        // Validate content type
        const allowed = ["video/mp4", "video/quicktime", "video/webm", "video/3gpp", "image/jpeg", "image/png", "image/gif"];
        if (!allowed.some((t) => file.type.startsWith(t.split("/")[0]))) {
          return { error: `Unsupported file type: ${file.type}` };
        }

        // Generate unique filename
        const ext = file.type.includes("mp4") ? ".mp4"
          : file.type.includes("quicktime") ? ".mov"
          : file.type.includes("webm") ? ".webm"
          : file.type.includes("3gpp") ? ".3gp"
          : file.type.includes("jpeg") ? ".jpg"
          : file.type.includes("png") ? ".png"
          : file.type.includes("gif") ? ".gif"
          : "";
        const filename = `${randomUUID()}${ext}`;
        const filepath = path.join(UPLOADS_DIR, filename);

        // Write file to disk
        const buffer = await file.arrayBuffer();
        await Bun.write(filepath, buffer);

        const url = `/uploads/${filename}`;
        const fullUrl = `http://${app.server?.hostname === "0.0.0.0" ? "localhost" : app.server?.hostname}:${PORT}${url}`;
        console.log(`[Upload] Saved ${filename} (${(buffer.byteLength / 1024 / 1024).toFixed(2)} MB) → ${fullUrl}`);

        return { ok: true, url, filename };
      } catch (err) {
        console.error("[Upload] Error:", err);
        return { error: "Upload failed" };
      }
    },
    {
      detail: { description: "Upload video/image file" },
    }
  )

  // ── Serve uploaded files ──
  .get(
    "/uploads/:filename",
    async ({ params, set }) => {
      const filepath = path.join(UPLOADS_DIR, params.filename);
      // Prevent directory traversal
      if (params.filename.includes("..") || params.filename.includes("/")) {
        set.status = 400;
        return { error: "Invalid filename" };
      }
      const file = Bun.file(filepath);
      if (!(await file.exists())) {
        set.status = 404;
        return { error: "File not found" };
      }
      set.headers["Content-Type"] = file.type;
      set.headers["Cache-Control"] = "public, max-age=31536000";
      return file;
    },
    {
      params: t.Object({ filename: t.String() }),
      detail: { description: "Serve uploaded files" },
    }
  )

  // ── Start ──
  .listen(PORT);

console.log(
  `🚀 ChainTok backend running at http://${app.server?.hostname}:${app.server?.port}`
);
console.log(`   Health:     GET  /`);
console.log(`   Feed:       GET  /feed?sort=latest|hot&limit=20&offset=0`);
console.log(`   Post:       GET  /post/:pubkey`);
console.log(`   Comments:   GET  /post/:pubkey/comments`);
console.log(`   User Posts: GET  /user/:pubkey/posts`);
console.log(`   Profile:    GET  /user/:pubkey/profile`);
console.log(`   Webhook:    POST /webhook`);
console.log(`   Upload:     POST /upload`);
console.log(`   Files:      GET  /uploads/:filename`);
