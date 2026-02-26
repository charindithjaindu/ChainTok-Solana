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
  getFollowingFeed,
  getPost,
  getPostsByCreator,
  getComments,
  upsertProfile,
  getProfileByAuthority,
  updateProfileMeta,
  recordLike,
  removeLike,
  getLikedPostPubkeys,
  followUser,
  unfollowUser,
  isFollowingUser,
  getFollowerCount,
  getFollowingCount,
  getFollowers,
  getFollowingList,
  recordTip,
  getTotalTips,
  getTipsForUser,
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
              recordLike(event.postPubkey, event.liker);
              likesProcessed++;
              break;

            case "PostUnliked":
              setLikeCount(event.postPubkey, event.newLikeCount);
              removeLike(event.postPubkey, event.liker);
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

            case "ProfileUpdated":
              console.log(`[Webhook] Profile updated: ${event.profilePubkey}`);
              break;

            case "UserFollowed":
              followUser(event.follower, event.following);
              break;

            case "UserUnfollowed":
              unfollowUser(event.follower, event.following);
              break;

            case "TipSent":
              recordTip({
                sender: event.tipper,
                receiver: event.creator,
                amountSol: event.amountLamports / 1_000_000_000,
                postPubkey: event.postPubkey,
                signature: "",
              });
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
      const sort = (query.sort ?? "latest") as string;
      const limit = Math.min(Math.max(parseInt(query.limit ?? "20"), 1), 100);
      const offset = Math.max(parseInt(query.offset ?? "0"), 0);
      const viewer = query.viewer ?? "";

      let posts: any[];
      if (sort === "following" && viewer) {
        posts = getFollowingFeed(viewer, limit, offset);
      } else {
        const feedSort = sort === "hot" || sort === "foryou" ? "hot" as const : "latest" as const;
        posts = getFeed(feedSort, limit, offset);
      }

      // Enrich with isLiked if viewer is provided
      if (viewer && posts.length > 0) {
        const pubkeys = posts.map((p: any) => p.pubkey);
        const likedSet = getLikedPostPubkeys(pubkeys, viewer);
        posts = posts.map((p: any) => ({ ...p, is_liked: likedSet.has(p.pubkey) }));
      }

      return posts;
    },
    {
      query: t.Object({
        sort: t.Optional(t.String()),
        limit: t.Optional(t.String()),
        offset: t.Optional(t.String()),
        viewer: t.Optional(t.String()),
      }),
      detail: { description: "Get post feed (sort: latest|hot|foryou|following)" },
    }
  )

  // ── Single Post ──
  .get(
    "/post/:pubkey",
    ({ params, query, set }) => {
      const post = getPost(params.pubkey);
      if (!post) {
        set.status = 404;
        return { error: "Post not found" };
      }
      const viewer = query?.viewer ?? "";
      if (viewer) {
        const likedSet = getLikedPostPubkeys([post.pubkey], viewer);
        return { ...post, is_liked: likedSet.has(post.pubkey) };
      }
      return post;
    },
    {
      params: t.Object({ pubkey: t.String() }),
      query: t.Object({ viewer: t.Optional(t.String()) }),
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
    ({ params, query, set }) => {
      const profile = getProfileByAuthority(params.pubkey);
      if (!profile) {
        set.status = 404;
        return { error: "Profile not found" };
      }
      const viewer = query?.viewer ?? "";
      const follower_count = getFollowerCount(params.pubkey);
      const following_count = getFollowingCount(params.pubkey);
      const total_tips = getTotalTips(params.pubkey);
      const is_following = viewer ? isFollowingUser(viewer, params.pubkey) : false;
      return { ...profile, follower_count, following_count, total_tips, is_following };
    },
    {
      params: t.Object({ pubkey: t.String() }),
      query: t.Object({ viewer: t.Optional(t.String()) }),
      detail: { description: "Get profile by wallet authority pubkey" },
    }
  )

  // ── Update User Profile (off-chain cache) ──
  .put(
    "/user/:pubkey/profile",
    ({ params, body, headers, set }) => {
      try {
        // Simple auth: x-wallet-address header must match the pubkey
        const walletAddr = headers["x-wallet-address"] ?? "";
        if (walletAddr !== params.pubkey) {
          set.status = 403;
          return { error: "Forbidden: wallet address mismatch" };
        }

        const { display_name, bio, pfp_uri } = body as {
          display_name?: string;
          bio?: string;
          pfp_uri?: string;
        };

        updateProfileMeta(params.pubkey, {
          display_name: display_name ?? '',
          bio: bio ?? '',
          pfp_uri: pfp_uri ?? '',
        });

        const profile = getProfileByAuthority(params.pubkey);
        return profile ?? { ok: true };
      } catch (err) {
        console.error("[Profile Update] Error:", err);
        set.status = 500;
        return { error: "Failed to update profile" };
      }
    },
    {
      params: t.Object({ pubkey: t.String() }),
      detail: { description: "Update user profile metadata (off-chain cache)" },
    }
  )

  // ── Follow User ──
  .post(
    "/user/:pubkey/follow",
    ({ params, headers, set }) => {
      const follower = headers["x-wallet-address"] ?? "";
      if (!follower) {
        set.status = 401;
        return { error: "Missing x-wallet-address header" };
      }
      if (follower === params.pubkey) {
        set.status = 400;
        return { error: "Cannot follow yourself" };
      }
      followUser(follower, params.pubkey);
      return { ok: true, follower_count: getFollowerCount(params.pubkey) };
    },
    {
      params: t.Object({ pubkey: t.String() }),
      detail: { description: "Follow a user" },
    }
  )

  // ── Unfollow User ──
  .delete(
    "/user/:pubkey/follow",
    ({ params, headers, set }) => {
      const follower = headers["x-wallet-address"] ?? "";
      if (!follower) {
        set.status = 401;
        return { error: "Missing x-wallet-address header" };
      }
      unfollowUser(follower, params.pubkey);
      return { ok: true, follower_count: getFollowerCount(params.pubkey) };
    },
    {
      params: t.Object({ pubkey: t.String() }),
      detail: { description: "Unfollow a user" },
    }
  )

  // ── Get Followers ──
  .get(
    "/user/:pubkey/followers",
    ({ params, query }) => {
      const limit = Math.min(Math.max(parseInt(query.limit ?? "50"), 1), 200);
      const offset = Math.max(parseInt(query.offset ?? "0"), 0);
      return {
        followers: getFollowers(params.pubkey, limit, offset),
        count: getFollowerCount(params.pubkey),
      };
    },
    {
      params: t.Object({ pubkey: t.String() }),
      query: t.Object({ limit: t.Optional(t.String()), offset: t.Optional(t.String()) }),
      detail: { description: "Get followers for a user" },
    }
  )

  // ── Get Following ──
  .get(
    "/user/:pubkey/following",
    ({ params, query }) => {
      const limit = Math.min(Math.max(parseInt(query.limit ?? "50"), 1), 200);
      const offset = Math.max(parseInt(query.offset ?? "0"), 0);
      return {
        following: getFollowingList(params.pubkey, limit, offset),
        count: getFollowingCount(params.pubkey),
      };
    },
    {
      params: t.Object({ pubkey: t.String() }),
      query: t.Object({ limit: t.Optional(t.String()), offset: t.Optional(t.String()) }),
      detail: { description: "Get users that this user follows" },
    }
  )

  // ── Record Tip ──
  .post(
    "/tip",
    ({ body, headers, set }) => {
      const sender = headers["x-wallet-address"] ?? "";
      if (!sender) {
        set.status = 401;
        return { error: "Missing x-wallet-address header" };
      }
      const { receiver, amount_sol, post_pubkey, signature } = body as {
        receiver: string;
        amount_sol: number;
        post_pubkey?: string;
        signature: string;
      };
      if (!receiver || !amount_sol || !signature) {
        set.status = 400;
        return { error: "Missing required fields: receiver, amount_sol, signature" };
      }
      recordTip({
        sender,
        receiver,
        amountSol: amount_sol,
        postPubkey: post_pubkey ?? "",
        signature,
      });
      return { ok: true, total_tips: getTotalTips(receiver) };
    },
    {
      detail: { description: "Record a tip transaction" },
    }
  )

  // ── Get User Tips ──
  .get(
    "/user/:pubkey/tips",
    ({ params, query }) => {
      const limit = Math.min(Math.max(parseInt(query.limit ?? "50"), 1), 200);
      const offset = Math.max(parseInt(query.offset ?? "0"), 0);
      return {
        tips: getTipsForUser(params.pubkey, limit, offset),
        total: getTotalTips(params.pubkey),
      };
    },
    {
      params: t.Object({ pubkey: t.String() }),
      query: t.Object({ limit: t.Optional(t.String()), offset: t.Optional(t.String()) }),
      detail: { description: "Get tips received by a user" },
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
                recordLike(event.postPubkey, event.liker);
                break;
              case "PostUnliked":
                setLikeCount(event.postPubkey, event.newLikeCount);
                removeLike(event.postPubkey, event.liker);
                break;
              case "CommentCreated":
                insertComment({ pubkey: event.commentPubkey, postPubkey: event.postPubkey, author: event.author, content: event.content, timestamp: event.timestamp });
                break;
              case "ProfileUpdated":
                break;
              case "UserFollowed":
                followUser(event.follower, event.following);
                break;
              case "UserUnfollowed":
                unfollowUser(event.follower, event.following);
                break;
              case "TipSent":
                recordTip({ sender: event.tipper, receiver: event.creator, amountSol: event.amountLamports / 1_000_000_000, postPubkey: event.postPubkey, signature: "" });
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

        // Determine effective MIME type (Android image_picker often sends application/octet-stream)
        let mimeType = file.type;
        const originalName = (file as any).name ?? "";
        const extMap: Record<string, string> = {
          ".mp4": "video/mp4", ".mov": "video/quicktime", ".webm": "video/webm",
          ".3gp": "video/3gpp", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
          ".png": "image/png", ".gif": "image/gif",
        };

        // Fallback: infer MIME from original filename if type is generic/missing
        if (!mimeType || mimeType === "application/octet-stream") {
          const nameLower = originalName.toLowerCase();
          for (const [ext, mime] of Object.entries(extMap)) {
            if (nameLower.endsWith(ext)) {
              mimeType = mime;
              break;
            }
          }
        }

        // Validate content type
        const allowed = ["video/mp4", "video/quicktime", "video/webm", "video/3gpp", "image/jpeg", "image/png", "image/gif"];
        if (!allowed.includes(mimeType) && !allowed.some((t) => mimeType.startsWith(t.split("/")[0]))) {
          // Last resort: accept if it looks like an image/video based on magic bytes later; for MVP just allow octet-stream
          if (mimeType !== "application/octet-stream") {
            return { error: `Unsupported file type: ${mimeType}` };
          }
          // Default to .jpg for octet-stream (most common from mobile photo pickers)
          mimeType = "image/jpeg";
        }

        // Generate unique filename
        const ext = mimeType.includes("mp4") ? ".mp4"
          : mimeType.includes("quicktime") ? ".mov"
            : mimeType.includes("webm") ? ".webm"
              : mimeType.includes("3gpp") ? ".3gp"
                : mimeType.includes("jpeg") ? ".jpg"
                  : mimeType.includes("png") ? ".png"
                    : mimeType.includes("gif") ? ".gif"
                      : ".jpg";
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
  `ChainTok backend running at http://${app.server?.hostname}:${app.server?.port}`
);
console.log(`   Health:     GET  /`);
console.log(`   Feed:       GET  /feed?sort=latest|hot|foryou|following&viewer=WALLET`);
console.log(`   Post:       GET  /post/:pubkey?viewer=WALLET`);
console.log(`   Comments:   GET  /post/:pubkey/comments`);
console.log(`   User Posts: GET  /user/:pubkey/posts`);
console.log(`   Profile:    GET  /user/:pubkey/profile?viewer=WALLET`);
console.log(`   Profile:    PUT  /user/:pubkey/profile`);
console.log(`   Follow:     POST /user/:pubkey/follow`);
console.log(`   Unfollow:   DELETE /user/:pubkey/follow`);
console.log(`   Followers:  GET  /user/:pubkey/followers`);
console.log(`   Following:  GET  /user/:pubkey/following`);
console.log(`   Tip:        POST /tip`);
console.log(`   Tips:       GET  /user/:pubkey/tips`);
console.log(`   Webhook:    POST /webhook`);
console.log(`   Sync:       POST /sync`);
console.log(`   Upload:     POST /upload`);
console.log(`   Files:      GET  /uploads/:filename`);
