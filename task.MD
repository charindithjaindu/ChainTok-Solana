ChainTok is an onchain TikTok-like app built for the Solana hackathon. The project includes:

- backend/: ElysiaJS (Bun runtime) server for receiving Helius webhooks, parsing Solana events, caching minimal data in SQLite, and providing API endpoints for feed and post details.
- frontend/: Flutter mobile app with vertical video feed UI, Solana Mobile Stack wallet connect, and direct transaction signing/sending to Solana RPC.
- soltok/: Anchor program for Solana, including smart contract code, migrations, and tests.

Architecture:
- Core data (posts, likes, comments) is fully onchain via Anchor program
- Backend acts as a fast read/cache layer, not a proxy for writes
- Frontend interacts directly with Solana for transactions
- Video posts are uploaded to Arweave and minted as compressed NFT posts

Backend Endpoints:
- POST /webhook: Receives Helius webhook events, updates SQLite cache
- GET /feed: Returns sorted JSON list of posts
- GET /post/:post_pubkey: Returns details for a single post

See README files in each subdirectory for setup and development instructions.