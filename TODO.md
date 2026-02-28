# ChainTok — TODO & Roadmap

> **TikTok × Solana** — short-form video platform where every post, like, comment, follow, and tip lives on-chain.

---

## ✅ Completed (Hackathon MVP)

### On-Chain (Anchor Program)
- [x] `create_profile` / `update_profile` — user profile PDA with display name, bio, pfp URI
- [x] `create_post` / `delete_post` — video posts with Arweave URI & caption, soft-delete
- [x] `like_post` / `unlike_post` — LikeRecord PDA prevents double-likes
- [x] `create_comment` — on-chain comments linked to posts
- [x] `follow_user` / `unfollow_user` — FollowRecord PDA, prevents self-follow
- [x] `tip_creator` — direct SOL transfer via CPI to System Program
- [x] Events emitted for every action (ProfileCreated, PostCreated, PostLiked, etc.)

### Backend (ElysiaJS / Bun / SQLite)
- [x] Helius webhook receiver — parses Anchor events from `Program data:` logs
- [x] `/sync` endpoint — polls devnet for recent txs (no Helius needed for dev)
- [x] Full CRUD: feed, post, comments, profile endpoints
- [x] `GET /feed?sort=latest|hot|foryou|following&viewer=WALLET` — isLiked enrichment
- [x] Follow / unfollow / followers / following endpoints
- [x] Tip recording & SOL earnings tracking
- [x] Profile auth via `x-wallet-address` header
- [x] File upload for video / images (local disk for MVP)
- [x] For You algorithm (like_count × 2 + comment_count × 3 + recency bonus)

### Frontend (Flutter)
- [x] Vertical swipe video feed (TikTok-style PageView)
- [x] Solana Mobile Stack wallet connection (MWA)
- [x] Direct on-chain transaction signing (create profile, post, like, comment)
- [x] Pull-to-refresh on feed
- [x] Heart animation with haptic feedback on like
- [x] Follow button on creator cards
- [x] SOL tipping bottom sheet (preset amounts: 0.01–1.0 SOL)
- [x] Share via native share sheet + Solscan deep links
- [x] Shimmer loading skeleton
- [x] Profile screen with follower / following counts & tips earned
- [x] Avatar & profile editing with photo upload
- [x] Video upload screen
- [x] Post success dialog with Solscan link + "Mint as cNFT" option
- [x] cNFT minting service (simulated — Bubblegum integration scaffolded)
- [x] Discover & Inbox placeholder screens
- [ ] iOS app

---

## 🔧 In Progress / Next Up

- [ ] **Single "For You" feed** — consolidate tabs into one curated feed (done)
- [ ] **Anchor test coverage** — add tests for `follow_user`, `unfollow_user`, `tip_creator`
- [ ] **Improve For You algorithm** — factor in viewer's follow graph & past likes
- [ ] **Video compression** — compress videos client-side before upload
- [ ] **Error toasts** — surface transaction failures to the user properly

---

## 🗺️ Roadmap

### Phase 1 — Hackathon Polish (current)
| Feature | Status |
|---|---|
| Single feed with For You algorithm | ✅ |
| On-chain follow / tip | ✅ |
| Profile with social stats | ✅ |
| Solscan links everywhere | ✅ |
| Video upload + post creation flow | ✅ |
| Anchor test suite for all instructions | 🔧 |

### Phase 2 — Post-Hackathon (Q2 2026)
| Feature | Description |
|---|---|
| **Tapestry social graph integration** | Migrate profiles, follows, likes, comments, and content to [Tapestry](https://docs.usetapestry.dev/) — a composable on-chain social graph protocol on Solana. Replace our custom SQLite read cache + webhook indexer with Tapestry's managed API (`socialfi` package). This gives us cross-app social graph interoperability (users carry their followers/following across all Tapestry-powered apps), faster onboarding via `findOrCreate` profile imports, and eliminates the need to maintain our own Borsh event parser and indexing infra. Backend becomes a thin proxy that forwards social operations to `api.usetapestry.dev/v1/` with our namespaced API key. |
| **Arweave / Shadow Drive storage** | Replace local file uploads with decentralized storage |
| **Compressed NFT posts (Bubblegum)** | Every post auto-minted as cNFT on Merkle tree |
| **Token-gated content** | Lock posts behind NFT / token ownership |
| **Creator tokens (SPL)** | Launch per-creator fan tokens |
| **Solana Pay QR codes** | Scan-to-tip via Solana Pay protocol |
| **Push notifications** | Notify on new followers, tips, likes |
| **Following / Discover tabs** | Multi-tab feed with algorithmic + chronological views |
| **Search & explore** | Search users, hashtags, trending content |

### Phase 3 — Growth (Q3 2026)
| Feature | Description |
|---|---|
| **Livestreaming** | Real-time streaming with on-chain tip rain |
| **DAO governance via Realms** | Community-driven moderation using [Realms](https://realms.today/) (SPL Governance). Create a ChainTok DAO where token holders vote on content moderation policies, creator verification, platform fee parameters, and feature proposals. Leverage Realms' proposal lifecycle (draft → voting → execution) with on-chain execution of approved governance actions. |
| **Creator analytics** | Dashboard with views, tips, engagement metrics |
| **Cross-chain bridge** | Accept tips in USDC, mSOL, or bridged ETH |
| **Desktop / web app** | Flutter web build + PWA support |
| **Content recommendations ML** | On-device model for personalized feed ranking |

### Phase 4 — Ecosystem (Q4 2026+)
| Feature | Description |
|---|---|
| **Creator marketplace** | Buy / sell cNFT content rights |
| **Ad revenue sharing** | On-chain ad protocol with transparent revenue split |
| **Verified badges** | On-chain identity verification (Civic, SNS) |
| **Multi-language** | i18n support for global launch |
| **Mobile-first SDK** | Let other apps embed ChainTok video feeds |

---

## 🏆 Hackathon Pitch Points

1. **Fully on-chain social graph** — profiles, posts, likes, follows, tips all on Solana
2. **Sub-second UX** — Solana's 400ms finality means likes & tips feel instant
3. **Creator-first economics** — direct SOL tipping with zero platform fees
4. **Compressed NFTs** — every post can be minted as a cNFT at <$0.001
5. **Mobile-native** — built with Solana Mobile Stack & MWA for phone-first experience
6. **Open protocol** — any app can read the on-chain data; no lock-in
7. **Scalable architecture** — backend is just a cache layer; all truth lives on-chain
8. **Tapestry-ready** — planned migration to [Tapestry](https://docs.usetapestry.dev/) for composable, cross-app social graph interoperability on Solana

---

## 📁 Project Structure

```
soltok/
├── backend/          # ElysiaJS + Bun + SQLite (read cache & API)
├── frontend/         # Flutter mobile app
├── soltok/           # Anchor program (Solana smart contract)
│   ├── programs/     # Rust source
│   ├── tests/        # Anchor test suite
│   └── target/       # Build artifacts & IDL
├── TODO.md           # This file
└── task.MD           # Project overview
```
