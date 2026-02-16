import type {
    HeliusTransaction,
    ChainTokEvent,
    PostCreatedEvent,
    PostLikedEvent,
} from "./types";

// ─── Config ─────────────────────────────────────────────────────────
const PROGRAM_ID = "ReplaceWithYourProgramId11111111111111111111";

// ─── Log message patterns ───────────────────────────────────────────
// Expected Anchor program log formats:
//   "Program log: PostCreated: <pubkey>,<creator>,<arweave_uri>,<caption>"
//   "Program log: PostLiked: <postPubkey>"

const POST_CREATED_PREFIX = "Program log: PostCreated: ";
const POST_LIKED_PREFIX = "Program log: PostLiked: ";

// ─── Parser ─────────────────────────────────────────────────────────

/**
 * Parse an array of Helius enriched transactions into ChainTok events.
 * Only processes transactions that involve our Anchor program.
 */
export function parseWebhookEvents(
    txs: HeliusTransaction[]
): ChainTokEvent[] {
    const events: ChainTokEvent[] = [];

    for (const tx of txs) {
        const logs = tx.logMessages ?? [];

        // Filter: only process if our program was invoked
        const involvesProgram = logs.some((log) => log.includes(PROGRAM_ID));
        if (!involvesProgram) continue;

        for (const log of logs) {
            // ── PostCreated ──
            if (log.startsWith(POST_CREATED_PREFIX)) {
                const data = log.slice(POST_CREATED_PREFIX.length);
                const parts = data.split(",");

                if (parts.length >= 3) {
                    const event: PostCreatedEvent = {
                        type: "PostCreated",
                        pubkey: parts[0].trim(),
                        creator: parts[1].trim(),
                        arweave_uri: parts[2].trim(),
                        caption: parts.slice(3).join(",").trim() || "",
                        timestamp: tx.timestamp,
                    };
                    events.push(event);
                }
            }

            // ── PostLiked ──
            if (log.startsWith(POST_LIKED_PREFIX)) {
                const postPubkey = log.slice(POST_LIKED_PREFIX.length).trim();
                if (postPubkey) {
                    const event: PostLikedEvent = {
                        type: "PostLiked",
                        postPubkey,
                    };
                    events.push(event);
                }
            }
        }
    }

    return events;
}
