import { Elysia, t } from "elysia";
import { cors } from "@elysiajs/cors";

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

// ─── Constants ──────────────────────────────────────────────────────
const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3000;

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
