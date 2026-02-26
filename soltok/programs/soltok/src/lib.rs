use anchor_lang::prelude::*;

declare_id!("ArteCcRQqj14sy5BaS7iHDU8EmYURYWFCLh4opB97vS2");

// ── Constants ───────────────────────────────────────────────────────────────

pub const MAX_URI_LEN: usize = 200;
pub const MAX_CAPTION_LEN: usize = 280;
pub const MAX_DISPLAY_NAME_LEN: usize = 50;
pub const MAX_BIO_LEN: usize = 160;
pub const MAX_PFP_URI_LEN: usize = 200;
pub const MAX_COMMENT_LEN: usize = 280;

#[program]
pub mod chain_tok_program {
    use super::*;

    // ── User Profile ────────────────────────────────────────────────────

    /// Initialize or update a user profile PDA.
    pub fn create_profile(
        ctx: Context<CreateProfile>,
        display_name: String,
        bio: String,
        pfp_uri: String,
    ) -> Result<()> {
        require!(display_name.len() <= MAX_DISPLAY_NAME_LEN, ChainTokError::FieldTooLong);
        require!(bio.len() <= MAX_BIO_LEN, ChainTokError::FieldTooLong);
        require!(pfp_uri.len() <= MAX_PFP_URI_LEN, ChainTokError::FieldTooLong);

        let profile = &mut ctx.accounts.profile;
        profile.authority = *ctx.accounts.authority.key;
        profile.display_name = display_name;
        profile.bio = bio;
        profile.pfp_uri = pfp_uri;
        profile.post_count = 0;
        profile.total_likes = 0;
        profile.created_at = Clock::get()?.unix_timestamp;
        profile.bump = ctx.bumps.profile;

        emit!(ProfileCreated {
            profile_pubkey: profile.key(),
            authority: profile.authority,
        });
        Ok(())
    }

    /// Update an existing user profile.
    pub fn update_profile(
        ctx: Context<UpdateProfile>,
        display_name: String,
        bio: String,
        pfp_uri: String,
    ) -> Result<()> {
        require!(display_name.len() <= MAX_DISPLAY_NAME_LEN, ChainTokError::FieldTooLong);
        require!(bio.len() <= MAX_BIO_LEN, ChainTokError::FieldTooLong);
        require!(pfp_uri.len() <= MAX_PFP_URI_LEN, ChainTokError::FieldTooLong);

        let profile = &mut ctx.accounts.profile;
        profile.display_name = display_name.clone();
        profile.bio = bio.clone();
        profile.pfp_uri = pfp_uri.clone();

        emit!(ProfileUpdated {
            profile_pubkey: profile.key(),
            authority: profile.authority,
            display_name,
            bio,
            pfp_uri,
        });
        Ok(())
    }

    // ── Posts ────────────────────────────────────────────────────────────

    /// Creates a new post PDA.
    /// Client passes `post_id` (e.g. unix-timestamp in ms) to make seed unique.
    pub fn create_post(
        ctx: Context<CreatePost>,
        post_id: u64,
        arweave_uri: String,
        caption: String,
    ) -> Result<()> {
        require!(arweave_uri.len() <= MAX_URI_LEN, ChainTokError::FieldTooLong);
        require!(caption.len() <= MAX_CAPTION_LEN, ChainTokError::FieldTooLong);

        let post = &mut ctx.accounts.post;
        post.creator = *ctx.accounts.creator.key;
        post.post_id = post_id;
        post.arweave_uri = arweave_uri;
        post.caption = caption;
        post.timestamp = Clock::get()?.unix_timestamp;
        post.like_count = 0;
        post.comment_count = 0;
        post.is_deleted = false;
        post.bump = ctx.bumps.post;

        // Increment creator's post_count
        let profile = &mut ctx.accounts.creator_profile;
        profile.post_count = profile.post_count.checked_add(1).ok_or(ChainTokError::Overflow)?;

        emit!(PostCreated {
            post_pubkey: post.key(),
            creator: post.creator,
            arweave_uri: post.arweave_uri.clone(),
            caption: post.caption.clone(),
            timestamp: post.timestamp,
        });

        msg!("Post created: {}", post.key());
        Ok(())
    }

    /// Soft-delete a post (only creator can call).
    pub fn delete_post(ctx: Context<DeletePost>) -> Result<()> {
        let post = &mut ctx.accounts.post;
        require!(!post.is_deleted, ChainTokError::AlreadyDeleted);
        post.is_deleted = true;

        let profile = &mut ctx.accounts.creator_profile;
        profile.post_count = profile.post_count.saturating_sub(1);

        emit!(PostDeleted {
            post_pubkey: post.key(),
            creator: post.creator,
        });
        Ok(())
    }

    // ── Likes ───────────────────────────────────────────────────────────

    /// Like a post. Creates a LikeRecord PDA → prevents double-likes.
    pub fn like_post(ctx: Context<LikePost>) -> Result<()> {
        require!(!ctx.accounts.post.is_deleted, ChainTokError::PostDeleted);

        let post = &mut ctx.accounts.post;
        post.like_count = post.like_count.checked_add(1).ok_or(ChainTokError::Overflow)?;

        let like_record = &mut ctx.accounts.like_record;
        like_record.liker = *ctx.accounts.liker.key;
        like_record.post = post.key();
        like_record.timestamp = Clock::get()?.unix_timestamp;
        like_record.bump = ctx.bumps.like_record;

        // Increment creator's total_likes
        let profile = &mut ctx.accounts.creator_profile;
        profile.total_likes = profile.total_likes.checked_add(1).ok_or(ChainTokError::Overflow)?;

        emit!(PostLiked {
            post_pubkey: post.key(),
            liker: *ctx.accounts.liker.key,
            new_like_count: post.like_count,
        });

        msg!("Liked post: {} → now {} likes", post.key(), post.like_count);
        Ok(())
    }

    /// Unlike a post. Closes the LikeRecord PDA → returns rent to liker.
    pub fn unlike_post(ctx: Context<UnlikePost>) -> Result<()> {
        require!(!ctx.accounts.post.is_deleted, ChainTokError::PostDeleted);

        let post = &mut ctx.accounts.post;
        post.like_count = post.like_count.saturating_sub(1);

        let profile = &mut ctx.accounts.creator_profile;
        profile.total_likes = profile.total_likes.saturating_sub(1);

        emit!(PostUnliked {
            post_pubkey: post.key(),
            liker: *ctx.accounts.liker.key,
            new_like_count: post.like_count,
        });

        msg!("Unliked post: {} → now {} likes", post.key(), post.like_count);
        Ok(())
    }

    // ── Comments ────────────────────────────────────────────────────────

    /// Add a comment to a post. Each comment is its own PDA.
    pub fn create_comment(
        ctx: Context<CreateComment>,
        comment_id: u64,
        content: String,
    ) -> Result<()> {
        require!(!ctx.accounts.post.is_deleted, ChainTokError::PostDeleted);
        require!(content.len() <= MAX_COMMENT_LEN, ChainTokError::FieldTooLong);

        let comment = &mut ctx.accounts.comment;
        comment.post = ctx.accounts.post.key();
        comment.author = *ctx.accounts.author.key;
        comment.comment_id = comment_id;
        comment.content = content;
        comment.timestamp = Clock::get()?.unix_timestamp;
        comment.bump = ctx.bumps.comment;

        let post = &mut ctx.accounts.post;
        post.comment_count = post.comment_count.checked_add(1).ok_or(ChainTokError::Overflow)?;

        emit!(CommentCreated {
            comment_pubkey: comment.key(),
            post_pubkey: post.key(),
            author: comment.author,
            content: comment.content.clone(),
            timestamp: comment.timestamp,
        });

        msg!("Comment on post: {}", post.key());
        Ok(())
    }

    // ── Follow / Unfollow ───────────────────────────────────────────────

    /// Follow a user. Creates a FollowRecord PDA → prevents double-follows.
    pub fn follow_user(ctx: Context<FollowUser>) -> Result<()> {
        require!(
            ctx.accounts.follower.key() != ctx.accounts.following.key(),
            ChainTokError::CannotFollowSelf
        );

        let record = &mut ctx.accounts.follow_record;
        record.follower = *ctx.accounts.follower.key;
        record.following = *ctx.accounts.following.key;
        record.timestamp = Clock::get()?.unix_timestamp;
        record.bump = ctx.bumps.follow_record;

        emit!(UserFollowed {
            follower: record.follower,
            following: record.following,
        });

        msg!("{} followed {}", record.follower, record.following);
        Ok(())
    }

    /// Unfollow a user. Closes the FollowRecord PDA → returns rent.
    pub fn unfollow_user(ctx: Context<UnfollowUser>) -> Result<()> {
        emit!(UserUnfollowed {
            follower: *ctx.accounts.follower.key,
            following: ctx.accounts.follow_record.following,
        });
        msg!("{} unfollowed {}", ctx.accounts.follower.key(), ctx.accounts.follow_record.following);
        Ok(())
    }

    // ── Tip Creator ─────────────────────────────────────────────────────

    /// Send a SOL tip to a post creator via system_program transfer.
    pub fn tip_creator(ctx: Context<TipCreator>, amount_lamports: u64) -> Result<()> {
        require!(amount_lamports > 0, ChainTokError::InvalidAmount);

        let ix = anchor_lang::solana_program::system_instruction::transfer(
            ctx.accounts.tipper.key,
            ctx.accounts.creator.key,
            amount_lamports,
        );
        anchor_lang::solana_program::program::invoke(
            &ix,
            &[
                ctx.accounts.tipper.to_account_info(),
                ctx.accounts.creator.to_account_info(),
            ],
        )?;

        emit!(TipSent {
            tipper: *ctx.accounts.tipper.key,
            creator: *ctx.accounts.creator.key,
            post_pubkey: ctx.accounts.post.key(),
            amount_lamports,
        });

        msg!("Tipped {} lamports to {}", amount_lamports, ctx.accounts.creator.key());
        Ok(())
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── Account Contexts ──────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

// ── Profile ─────────────────────────────────────────────────────────────────

#[derive(Accounts)]
pub struct CreateProfile<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    #[account(
        init,
        payer = authority,
        space = UserProfile::SIZE,
        seeds = [b"profile", authority.key().as_ref()],
        bump,
    )]
    pub profile: Account<'info, UserProfile>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdateProfile<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    #[account(
        mut,
        seeds = [b"profile", authority.key().as_ref()],
        bump = profile.bump,
        has_one = authority,
    )]
    pub profile: Account<'info, UserProfile>,
}

// ── CreatePost ──────────────────────────────────────────────────────────────

#[derive(Accounts)]
#[instruction(post_id: u64, arweave_uri: String, caption: String)]
pub struct CreatePost<'info> {
    #[account(mut)]
    pub creator: Signer<'info>,

    #[account(
        mut,
        seeds = [b"profile", creator.key().as_ref()],
        bump = creator_profile.bump,
        constraint = creator_profile.authority == creator.key() @ ChainTokError::Unauthorized,
    )]
    pub creator_profile: Account<'info, UserProfile>,

    #[account(
        init,
        payer = creator,
        space = Post::SIZE,
        seeds = [
            b"post",
            creator.key().as_ref(),
            &post_id.to_le_bytes(),
        ],
        bump,
    )]
    pub post: Account<'info, Post>,

    pub system_program: Program<'info, System>,
}

// ── DeletePost ──────────────────────────────────────────────────────────────

#[derive(Accounts)]
pub struct DeletePost<'info> {
    #[account(mut)]
    pub creator: Signer<'info>,

    #[account(
        mut,
        seeds = [b"profile", creator.key().as_ref()],
        bump = creator_profile.bump,
    )]
    pub creator_profile: Account<'info, UserProfile>,

    #[account(
        mut,
        has_one = creator @ ChainTokError::Unauthorized,
    )]
    pub post: Account<'info, Post>,
}

// ── LikePost ────────────────────────────────────────────────────────────────

#[derive(Accounts)]
pub struct LikePost<'info> {
    #[account(mut)]
    pub liker: Signer<'info>,

    #[account(
        mut,
        seeds = [
            b"post",
            post.creator.as_ref(),
            &post.post_id.to_le_bytes(),
        ],
        bump = post.bump,
    )]
    pub post: Account<'info, Post>,

    /// The post creator's profile — to increment total_likes
    #[account(
        mut,
        seeds = [b"profile", post.creator.as_ref()],
        bump = creator_profile.bump,
    )]
    pub creator_profile: Account<'info, UserProfile>,

    /// PDA that records this user liked this post (prevents double-like)
    #[account(
        init,
        payer = liker,
        space = LikeRecord::SIZE,
        seeds = [b"like", post.key().as_ref(), liker.key().as_ref()],
        bump,
    )]
    pub like_record: Account<'info, LikeRecord>,

    pub system_program: Program<'info, System>,
}

// ── UnlikePost ──────────────────────────────────────────────────────────────

#[derive(Accounts)]
pub struct UnlikePost<'info> {
    #[account(mut)]
    pub liker: Signer<'info>,

    #[account(
        mut,
        seeds = [
            b"post",
            post.creator.as_ref(),
            &post.post_id.to_le_bytes(),
        ],
        bump = post.bump,
    )]
    pub post: Account<'info, Post>,

    /// The post creator's profile — to decrement total_likes
    #[account(
        mut,
        seeds = [b"profile", post.creator.as_ref()],
        bump = creator_profile.bump,
    )]
    pub creator_profile: Account<'info, UserProfile>,

    /// Close the like record → rent goes back to liker
    #[account(
        mut,
        seeds = [b"like", post.key().as_ref(), liker.key().as_ref()],
        bump = like_record.bump,
        close = liker,
    )]
    pub like_record: Account<'info, LikeRecord>,
}

// ── CreateComment ───────────────────────────────────────────────────────────

#[derive(Accounts)]
#[instruction(comment_id: u64, content: String)]
pub struct CreateComment<'info> {
    #[account(mut)]
    pub author: Signer<'info>,

    #[account(mut)]
    pub post: Account<'info, Post>,

    #[account(
        init,
        payer = author,
        space = Comment::SIZE,
        seeds = [
            b"comment",
            post.key().as_ref(),
            author.key().as_ref(),
            &comment_id.to_le_bytes(),
        ],
        bump,
    )]
    pub comment: Account<'info, Comment>,

    pub system_program: Program<'info, System>,
}

// ── FollowUser ──────────────────────────────────────────────────────────────

#[derive(Accounts)]
pub struct FollowUser<'info> {
    #[account(mut)]
    pub follower: Signer<'info>,

    /// CHECK: The user to follow (just a pubkey, no data needed)
    pub following: UncheckedAccount<'info>,

    #[account(
        init,
        payer = follower,
        space = FollowRecord::SIZE,
        seeds = [b"follow", follower.key().as_ref(), following.key().as_ref()],
        bump,
    )]
    pub follow_record: Account<'info, FollowRecord>,

    pub system_program: Program<'info, System>,
}

// ── UnfollowUser ────────────────────────────────────────────────────────────

#[derive(Accounts)]
pub struct UnfollowUser<'info> {
    #[account(mut)]
    pub follower: Signer<'info>,

    /// CHECK: The user to unfollow
    pub following: UncheckedAccount<'info>,

    #[account(
        mut,
        seeds = [b"follow", follower.key().as_ref(), following.key().as_ref()],
        bump = follow_record.bump,
        close = follower,
    )]
    pub follow_record: Account<'info, FollowRecord>,
}

// ── TipCreator ──────────────────────────────────────────────────────────────

#[derive(Accounts)]
pub struct TipCreator<'info> {
    #[account(mut)]
    pub tipper: Signer<'info>,

    /// CHECK: The creator receiving the tip — validated against post.creator
    #[account(
        mut,
        constraint = creator.key() == post.creator @ ChainTokError::Unauthorized,
    )]
    pub creator: UncheckedAccount<'info>,

    /// The post being tipped
    #[account(
        constraint = !post.is_deleted @ ChainTokError::PostDeleted,
    )]
    pub post: Account<'info, Post>,

    pub system_program: Program<'info, System>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── Data Accounts ─────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

#[account]
pub struct UserProfile {
    pub authority: Pubkey,          // wallet that owns this profile
    pub display_name: String,       // max 50 chars
    pub bio: String,                // max 160 chars
    pub pfp_uri: String,            // profile pic URI (Arweave)
    pub post_count: u64,
    pub total_likes: u64,           // total likes across all posts
    pub created_at: i64,
    pub bump: u8,
}

impl UserProfile {
    pub const SIZE: usize = 8          // discriminator
        + 32                           // authority
        + (4 + MAX_DISPLAY_NAME_LEN)   // display_name
        + (4 + MAX_BIO_LEN)            // bio
        + (4 + MAX_PFP_URI_LEN)        // pfp_uri
        + 8                            // post_count
        + 8                            // total_likes
        + 8                            // created_at
        + 1;                           // bump
}

#[account]
pub struct Post {
    pub creator: Pubkey,
    pub post_id: u64,                 // client-generated unique id (e.g. unix ms)
    pub arweave_uri: String,          // "https://arweave.net/abc123"
    pub caption: String,
    pub timestamp: i64,               // set by Clock on-chain
    pub like_count: u64,
    pub comment_count: u64,
    pub is_deleted: bool,
    pub bump: u8,
}

impl Post {
    /// Fixed size using MAX constants — ensures accounts have room for max-length data
    pub const SIZE: usize = 8         // discriminator
        + 32                           // creator
        + 8                            // post_id
        + (4 + MAX_URI_LEN)            // arweave_uri
        + (4 + MAX_CAPTION_LEN)        // caption
        + 8                            // timestamp
        + 8                            // like_count
        + 8                            // comment_count
        + 1                            // is_deleted
        + 1;                           // bump

    /// Legacy dynamic sizing (kept for reference)
    pub fn size(arweave_uri: &str, caption: &str) -> usize {
        8 + 32 + 8
        + (4 + arweave_uri.len())
        + (4 + caption.len())
        + 8 + 8 + 8 + 1 + 1
    }
}

#[account]
pub struct LikeRecord {
    pub liker: Pubkey,
    pub post: Pubkey,
    pub timestamp: i64,
    pub bump: u8,
}

impl LikeRecord {
    pub const SIZE: usize = 8         // discriminator
        + 32                           // liker
        + 32                           // post
        + 8                            // timestamp
        + 1;                           // bump
}

#[account]
pub struct FollowRecord {
    pub follower: Pubkey,
    pub following: Pubkey,
    pub timestamp: i64,
    pub bump: u8,
}

impl FollowRecord {
    pub const SIZE: usize = 8         // discriminator
        + 32                           // follower
        + 32                           // following
        + 8                            // timestamp
        + 1;                           // bump
}

#[account]
pub struct Comment {
    pub post: Pubkey,
    pub author: Pubkey,
    pub comment_id: u64,
    pub content: String,
    pub timestamp: i64,
    pub bump: u8,
}

impl Comment {
    /// Fixed size using MAX constant
    pub const SIZE: usize = 8         // discriminator
        + 32                           // post
        + 32                           // author
        + 8                            // comment_id
        + (4 + MAX_COMMENT_LEN)        // content
        + 8                            // timestamp
        + 1;                           // bump

    /// Legacy dynamic sizing (kept for reference)
    pub fn size(content: &str) -> usize {
        8 + 32 + 32 + 8 + (4 + content.len()) + 8 + 1
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── Events ────────────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

#[event]
pub struct ProfileCreated {
    pub profile_pubkey: Pubkey,
    pub authority: Pubkey,
}

#[event]
pub struct ProfileUpdated {
    pub profile_pubkey: Pubkey,
    pub authority: Pubkey,
    pub display_name: String,
    pub bio: String,
    pub pfp_uri: String,
}

#[event]
pub struct PostCreated {
    pub post_pubkey: Pubkey,
    pub creator: Pubkey,
    pub arweave_uri: String,
    pub caption: String,
    pub timestamp: i64,
}

#[event]
pub struct PostDeleted {
    pub post_pubkey: Pubkey,
    pub creator: Pubkey,
}

#[event]
pub struct PostLiked {
    pub post_pubkey: Pubkey,
    pub liker: Pubkey,
    pub new_like_count: u64,
}

#[event]
pub struct PostUnliked {
    pub post_pubkey: Pubkey,
    pub liker: Pubkey,
    pub new_like_count: u64,
}

#[event]
pub struct CommentCreated {
    pub comment_pubkey: Pubkey,
    pub post_pubkey: Pubkey,
    pub author: Pubkey,
    pub content: String,
    pub timestamp: i64,
}

#[event]
pub struct UserFollowed {
    pub follower: Pubkey,
    pub following: Pubkey,
}

#[event]
pub struct UserUnfollowed {
    pub follower: Pubkey,
    pub following: Pubkey,
}

#[event]
pub struct TipSent {
    pub tipper: Pubkey,
    pub creator: Pubkey,
    pub post_pubkey: Pubkey,
    pub amount_lamports: u64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── Errors ────────────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

#[error_code]
pub enum ChainTokError {
    #[msg("Arithmetic overflow")]
    Overflow,
    #[msg("Field exceeds max length")]
    FieldTooLong,
    #[msg("Unauthorized action")]
    Unauthorized,
    #[msg("Post has been deleted")]
    PostDeleted,
    #[msg("Already deleted")]
    AlreadyDeleted,
    #[msg("Cannot follow yourself")]
    CannotFollowSelf,
    #[msg("Invalid amount")]
    InvalidAmount,
}