// ─── Constants ──────────────────────────────────────────────────────
export const PROGRAM_ID = "ArteCcRQqj14sy5BaS7iHDU8EmYURYWFCLh4opB97vS2";

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

export interface Comment {
  pubkey: string;
  post_pubkey: string;
  author: string;
  content: string;
  timestamp: number;
}

export interface Profile {
  pubkey: string;
  authority: string;
  display_name: string;
  bio: string;
  pfp_uri: string;
  created_at: number;
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

// ─── Parsed Anchor Events ──────────────────────────────────────────
export interface ProfileCreatedEvent {
  type: "ProfileCreated";
  profilePubkey: string;
  authority: string;
}

export interface PostCreatedEvent {
  type: "PostCreated";
  postPubkey: string;
  creator: string;
  arweaveUri: string;
  caption: string;
  timestamp: number;
}

export interface PostDeletedEvent {
  type: "PostDeleted";
  postPubkey: string;
  creator: string;
}

export interface PostLikedEvent {
  type: "PostLiked";
  postPubkey: string;
  liker: string;
  newLikeCount: number;
}

export interface PostUnlikedEvent {
  type: "PostUnliked";
  postPubkey: string;
  liker: string;
  newLikeCount: number;
}

export interface CommentCreatedEvent {
  type: "CommentCreated";
  commentPubkey: string;
  postPubkey: string;
  author: string;
  content: string;
  timestamp: number;
}

export interface ProfileUpdatedEvent {
  type: "ProfileUpdated";
  profilePubkey: string;
  authority: string;
}

export interface UserFollowedEvent {
  type: "UserFollowed";
  follower: string;
  following: string;
  timestamp: number;
}

export interface UserUnfollowedEvent {
  type: "UserUnfollowed";
  follower: string;
  following: string;
}

export interface TipSentEvent {
  type: "TipSent";
  tipper: string;
  creator: string;
  amountLamports: number;
  postPubkey: string;
}

export type ChainTokEvent =
  | ProfileCreatedEvent
  | PostCreatedEvent
  | PostDeletedEvent
  | PostLikedEvent
  | PostUnlikedEvent
  | CommentCreatedEvent
  | ProfileUpdatedEvent
  | UserFollowedEvent
  | UserUnfollowedEvent
  | TipSentEvent;
