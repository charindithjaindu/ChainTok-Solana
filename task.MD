You are an expert Solana + ElysiaJS + Flutter full-stack developer helping build an onchain TikTok-like app ("ChainTok") for a Solana hackathon.

Project structure:
- /backend → ElysiaJS (Bun runtime) minimal indexer server
- /frontend → Flutter mobile app (vertical video feed, wallet connect via Solana Mobile Stack)

Architecture goals (minimal backend):
- Core data (posts, likes, comments) is fully onchain via Anchor program on Solana.
- Backend only acts as a fast read/cache layer: receives Helius webhooks → parses events → upserts minimal data to SQLite.
- No heavy DB — use Bun's built-in sqlite3 or better-sqlite3.
- Frontend (Flutter) signs & sends transactions directly to Solana RPC (no backend proxy for writes).
- Feed: Flutter calls backend API → gets sorted JSON list of recent/hot posts (arweave_uri, caption, creator_pubkey, like_count, timestamp).
- MVP features: post video (upload to Arweave → mint compressed NFT post), like post (onchain tx), infinite chronological/hot feed.

Backend tech:
- Bun + ElysiaJS latest (2026 versions)
- @solana/web3.js ^2.x
- @metaplex-foundation/mpl-core (for compressed NFTs) or @metaplex-foundation/js
- Helius webhook parsing (expect POST with array of transactions)
- Database: bun:sqlite (file-based, zero config) or better-sqlite3
- Endpoints needed (start with these):
  - POST /webhook (Helius webhook receiver, verify signature if possible)
  - GET /feed?sort=latest|hot&limit=20&offset=0 (returns array of post objects)
  - GET /post/:post_pubkey (single post details)
  - Later: GET /user/:pubkey/posts

First tasks for backend (do step-by-step):
1. Create basic Elysia server in src/index.ts that listens on port 3000 with CORS enabled (allow * for dev).
2. Add a simple health endpoint: GET / → { "status": "ok" }
3. Set up bun:sqlite — create db file ./data/chainTok.db with one table:
   CREATE TABLE IF NOT EXISTS posts (
     pubkey TEXT PRIMARY KEY,
     creator TEXT NOT NULL,
     arweave_uri TEXT NOT NULL,
     caption TEXT,
     like_count INTEGER DEFAULT 0,
     comment_count INTEGER DEFAULT 0,
     timestamp INTEGER NOT NULL,
     updated_at INTEGER NOT NULL
   );
   CREATE INDEX IF NOT EXISTS idx_timestamp ON posts(timestamp);
   CREATE INDEX IF NOT EXISTS idx_like_count ON posts(like_count);
4. Add POST /webhook endpoint:
   - Expect body as Helius webhook format (array of enriched transactions)
   - For each tx, check if it contains your Anchor program ID
   - Parse logs/instructions for "create_post" or "like_post" events (assume simple discriminator or log messages like "PostCreated: <pubkey>")
   - If new post → insert into DB
   - If like → UPDATE posts SET like_count = like_count + 1 WHERE pubkey = ?
   - Return 200 OK quickly (Helius expects fast response)
5. Add GET /feed endpoint:
   - If sort=latest → SELECT * FROM posts ORDER BY timestamp DESC LIMIT ? OFFSET ?
   - If sort=hot → SELECT * FROM posts ORDER BY like_count DESC, timestamp DESC LIMIT ? OFFSET ?
   - Return JSON array of { pubkey, creator, arweave_uri, caption, like_count, ... }

Give me complete, runnable code for src/index.ts (or main file) with imports.
Use TypeScript, add types where helpful.
Include error handling basics.
Show how to run: bun run src/index.ts

After this is working, next I'll ask for Anchor program skeleton + Flutter wallet connect + video upload flow.

Assume Anchor program ID is: ReplaceWithYourProgramId11111111111111111111
Helius RPC: https://mainnet.helius-rpc.com/?api-key=YOUR_KEY (I'll fill later)

Start coding the backend skeleton now.