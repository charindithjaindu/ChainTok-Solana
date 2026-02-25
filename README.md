# ChainTok Full-Stack Project

This repository contains the complete source code for ChainTok, an onchain TikTok-like app built for the Solana hackathon. The project leverages Solana, Anchor, ElysiaJS (Bun runtime), and Flutter to deliver a decentralized vertical video feed experience.

## Project Structure

- **backend/**
  - ElysiaJS server (Bun runtime)
  - Receives Helius webhooks, parses Solana events, and caches minimal data in SQLite
  - Provides API endpoints for feed and post details
  - Technologies: Bun, ElysiaJS, @solana/web3.js, @metaplex-foundation/mpl-core, bun:sqlite

- **frontend/**
  - Flutter mobile app
  - Vertical video feed UI
  - Wallet connect via Solana Mobile Stack
  - Signs and sends transactions directly to Solana RPC
  - Technologies: Flutter, Dart

- **soltok/**
  - Anchor program for Solana
  - Contains smart contract code, migrations, and tests
  - Technologies: Rust, Anchor, TypeScript (for tests)

## Architecture Overview

- Core data (posts, likes, comments) is fully onchain via Anchor program
- Backend acts as a fast read/cache layer, not a proxy for writes
- Frontend interacts directly with Solana for transactions
- Video posts are uploaded to Arweave and minted as compressed NFT posts

## Backend Endpoints
- `POST /webhook`: Receives Helius webhook events, updates SQLite cache
- `GET /feed`: Returns sorted JSON list of posts
- `GET /post/:post_pubkey`: Returns details for a single post

## Getting Started

### Backend
- See backend/README.md for setup and development instructions

### Frontend
- See frontend/README.md for Flutter app setup

### Soltok (Anchor Program)
- See soltok/ for smart contract, migrations, and tests

## License
ISC

---
This README documents all components and features currently included in the ChainTok project:

- **backend/**: ElysiaJS server (Bun runtime) for receiving Helius webhooks, parsing Solana events, caching minimal data in SQLite, and providing API endpoints for feed and post details.
- **frontend/**: Flutter mobile app with vertical video feed UI, Solana Mobile Stack wallet connect, and direct transaction signing/sending to Solana RPC.
- **soltok/**: Anchor program for Solana, including smart contract code, migrations, and tests.

Features:
- Core data (posts, likes, comments) is fully onchain via Anchor program
- Backend acts as a fast read/cache layer, not a proxy for writes
- Frontend interacts directly with Solana for transactions
- Video posts are uploaded to Arweave and minted as compressed NFT posts

Backend Endpoints:
- `POST /webhook`: Receives Helius webhook events, updates SQLite cache
- `GET /feed`: Returns sorted JSON list of posts
- `GET /post/:post_pubkey`: Returns details for a single post

For setup and development instructions, see the README files in each subdirectory.