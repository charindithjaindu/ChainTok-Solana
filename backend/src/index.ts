import { Elysia, t } from "elysia";
import { cors } from "@elysiajs/cors";

import { upsertPost, incrementLike, getFeed, getPost } from "./db";
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
        let likesProcessed = 0;

        for (const event of events) {
          switch (event.type) {
            case "PostCreated":
              upsertPost({
                pubkey: event.pubkey,
                creator: event.creator,
                arweave_uri: event.arweave_uri,
                caption: event.caption,
                timestamp: event.timestamp,
              });
              postsCreated++;
              break;

            case "PostLiked":
              incrementLike(event.postPubkey);
              likesProcessed++;
              break;
          }
        }

        console.log(
          `[Webhook] Processed ${events.length} events → ${postsCreated} posts created, ${likesProcessed} likes`
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

  // ── Single Post Endpoint ──
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
      params: t.Object({
        pubkey: t.String(),
      }),
      detail: { description: "Get single post by pubkey" },
    }
  )

  // ── Start ──
  .listen(PORT);

console.log(
  `🚀 ChainTok backend running at http://${app.server?.hostname}:${app.server?.port}`
);
console.log(`   Health:  GET  /`);
console.log(`   Feed:    GET  /feed?sort=latest|hot&limit=20&offset=0`);
console.log(`   Post:    GET  /post/:pubkey`);
console.log(`   Webhook: POST /webhook`);
