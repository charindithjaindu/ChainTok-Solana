// ─── Database Row Types ─────────────────────────────────────────────
export interface Post {
    pubkey: string;
    creator: string;
    arweave_uri: string;
    caption: string | null;
    like_count: number;
    comment_count: number;
    timestamp: number;
    updated_at: number;
}

// ─── Helius Webhook Types ───────────────────────────────────────────
export interface HeliusTransaction {
    description: string;
    type: string;
    source: string;
    signature: string;
    slot: number;
    timestamp: number;
    nativeTransfers: unknown[];
    tokenTransfers: unknown[];
    accountData: unknown[];
    instructions: unknown[];
    events: Record<string, unknown>;
    logMessages?: string[];
}

export type WebhookPayload = HeliusTransaction[];

// ─── Parsed Events ─────────────────────────────────────────────────
export interface PostCreatedEvent {
    type: "PostCreated";
    pubkey: string;
    creator: string;
    arweave_uri: string;
    caption: string;
    timestamp: number;
}

export interface PostLikedEvent {
    type: "PostLiked";
    postPubkey: string;
}

export type ChainTokEvent = PostCreatedEvent | PostLikedEvent;
