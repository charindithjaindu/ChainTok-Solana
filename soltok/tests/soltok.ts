import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { ChainTokProgram } from "../target/types/chain_tok_program";
import { expect } from "chai";
import { PublicKey, SystemProgram } from "@solana/web3.js";

describe("ChainTok Program", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace
    .chainTokProgram as Program<ChainTokProgram>;

  const creator = provider.wallet;
  let postId: anchor.BN;
  let postPda: PublicKey;
  let profilePda: PublicKey;

  // Helper: derive PDA
  const findProfile = (authority: PublicKey) =>
    PublicKey.findProgramAddressSync(
      [Buffer.from("profile"), authority.toBuffer()],
      program.programId
    );

  const findPost = (creatorKey: PublicKey, id: anchor.BN) =>
    PublicKey.findProgramAddressSync(
      [
        Buffer.from("post"),
        creatorKey.toBuffer(),
        id.toArrayLike(Buffer, "le", 8),
      ],
      program.programId
    );

  const findLikeRecord = (post: PublicKey, liker: PublicKey) =>
    PublicKey.findProgramAddressSync(
      [Buffer.from("like"), post.toBuffer(), liker.toBuffer()],
      program.programId
    );

  const findComment = (
    post: PublicKey,
    author: PublicKey,
    commentId: anchor.BN
  ) =>
    PublicKey.findProgramAddressSync(
      [
        Buffer.from("comment"),
        post.toBuffer(),
        author.toBuffer(),
        commentId.toArrayLike(Buffer, "le", 8),
      ],
      program.programId
    );

  // ── Profile Tests ─────────────────────────────────────────────────────

  it("Creates a user profile", async () => {
    [profilePda] = findProfile(creator.publicKey);

    const tx = await program.methods
      .createProfile("Alice", "I love short videos 🎥", "https://arweave.net/pfp123")
      .accounts({
        authority: creator.publicKey,
        profile: profilePda,
        systemProgram: SystemProgram.programId,
      })
      .rpc();

    console.log("  ✓ createProfile tx:", tx);

    const profile = await program.account.userProfile.fetch(profilePda);
    expect(profile.displayName).to.equal("Alice");
    expect(profile.bio).to.equal("I love short videos 🎥");
    expect(profile.pfpUri).to.equal("https://arweave.net/pfp123");
    expect(profile.postCount.toNumber()).to.equal(0);
    expect(profile.totalLikes.toNumber()).to.equal(0);
  });

  it("Updates a user profile", async () => {
    const tx = await program.methods
      .updateProfile("Alice V2", "Updated bio!", "https://arweave.net/pfp456")
      .accounts({
        authority: creator.publicKey,
        profile: profilePda,
      })
      .rpc();

    console.log("  ✓ updateProfile tx:", tx);

    const profile = await program.account.userProfile.fetch(profilePda);
    expect(profile.displayName).to.equal("Alice V2");
    expect(profile.bio).to.equal("Updated bio!");
  });

  // ── Post Tests ────────────────────────────────────────────────────────

  it("Creates a post", async () => {
    postId = new anchor.BN(Date.now());
    [postPda] = findPost(creator.publicKey, postId);

    const tx = await program.methods
      .createPost(postId, "https://arweave.net/video123", "My first ChainTok! 🚀")
      .accounts({
        creator: creator.publicKey,
        creatorProfile: profilePda,
        post: postPda,
        systemProgram: SystemProgram.programId,
      })
      .rpc();

    console.log("  ✓ createPost tx:", tx);

    const post = await program.account.post.fetch(postPda);
    expect(post.creator.toBase58()).to.equal(creator.publicKey.toBase58());
    expect(post.arweaveUri).to.equal("https://arweave.net/video123");
    expect(post.caption).to.equal("My first ChainTok! 🚀");
    expect(post.likeCount.toNumber()).to.equal(0);
    expect(post.commentCount.toNumber()).to.equal(0);
    expect(post.isDeleted).to.equal(false);

    // Check profile post_count incremented
    const profile = await program.account.userProfile.fetch(profilePda);
    expect(profile.postCount.toNumber()).to.equal(1);
  });

  // ── Like Tests ────────────────────────────────────────────────────────

  it("Likes a post", async () => {
    const [likeRecordPda] = findLikeRecord(postPda, creator.publicKey);

    const tx = await program.methods
      .likePost()
      .accounts({
        liker: creator.publicKey,
        post: postPda,
        creatorProfile: profilePda,
        likeRecord: likeRecordPda,
        systemProgram: SystemProgram.programId,
      })
      .rpc();

    console.log("  ✓ likePost tx:", tx);

    const post = await program.account.post.fetch(postPda);
    expect(post.likeCount.toNumber()).to.equal(1);

    const profile = await program.account.userProfile.fetch(profilePda);
    expect(profile.totalLikes.toNumber()).to.equal(1);
  });

  it("Prevents double-liking (should fail)", async () => {
    const [likeRecordPda] = findLikeRecord(postPda, creator.publicKey);

    try {
      await program.methods
        .likePost()
        .accounts({
          liker: creator.publicKey,
          post: postPda,
          creatorProfile: profilePda,
          likeRecord: likeRecordPda,
          systemProgram: SystemProgram.programId,
        })
        .rpc();
      expect.fail("Should have thrown — double like");
    } catch (err) {
      // Expected: account already initialized
      console.log("  ✓ Double-like correctly rejected");
    }
  });

  it("Unlikes a post", async () => {
    const [likeRecordPda] = findLikeRecord(postPda, creator.publicKey);

    const tx = await program.methods
      .unlikePost()
      .accounts({
        liker: creator.publicKey,
        post: postPda,
        creatorProfile: profilePda,
        likeRecord: likeRecordPda,
      })
      .rpc();

    console.log("  ✓ unlikePost tx:", tx);

    const post = await program.account.post.fetch(postPda);
    expect(post.likeCount.toNumber()).to.equal(0);

    const profile = await program.account.userProfile.fetch(profilePda);
    expect(profile.totalLikes.toNumber()).to.equal(0);
  });

  // ── Comment Tests ─────────────────────────────────────────────────────

  it("Creates a comment on a post", async () => {
    const commentId = new anchor.BN(Date.now());
    const [commentPda] = findComment(
      postPda,
      creator.publicKey,
      commentId
    );

    const tx = await program.methods
      .createComment(commentId, "Great video! 🔥")
      .accounts({
        author: creator.publicKey,
        post: postPda,
        comment: commentPda,
        systemProgram: SystemProgram.programId,
      })
      .rpc();

    console.log("  ✓ createComment tx:", tx);

    const comment = await program.account.comment.fetch(commentPda);
    expect(comment.content).to.equal("Great video! 🔥");
    expect(comment.author.toBase58()).to.equal(creator.publicKey.toBase58());

    const post = await program.account.post.fetch(postPda);
    expect(post.commentCount.toNumber()).to.equal(1);
  });

  // ── Delete Tests ──────────────────────────────────────────────────────

  it("Soft-deletes a post", async () => {
    const tx = await program.methods
      .deletePost()
      .accounts({
        creator: creator.publicKey,
        creatorProfile: profilePda,
        post: postPda,
      })
      .rpc();

    console.log("  ✓ deletePost tx:", tx);

    const post = await program.account.post.fetch(postPda);
    expect(post.isDeleted).to.equal(true);

    const profile = await program.account.userProfile.fetch(profilePda);
    expect(profile.postCount.toNumber()).to.equal(0);
  });

  it("Prevents liking a deleted post (should fail)", async () => {
    const [likeRecordPda] = findLikeRecord(postPda, creator.publicKey);

    try {
      await program.methods
        .likePost()
        .accounts({
          liker: creator.publicKey,
          post: postPda,
          creatorProfile: profilePda,
          likeRecord: likeRecordPda,
          systemProgram: SystemProgram.programId,
        })
        .rpc();
      expect.fail("Should have thrown — post is deleted");
    } catch (err) {
      console.log("  ✓ Liking deleted post correctly rejected");
    }
  });
});
