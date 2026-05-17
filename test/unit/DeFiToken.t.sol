// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/governance/DeFiToken.sol";

contract DeFiTokenTest is Test {
    DeFiToken token;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 constant MAX_SUPPLY = 100_000_000e18;

    function setUp() public {
        vm.prank(owner);
        token = new DeFiToken(owner, INITIAL_SUPPLY);
    }

    // ─── Metadata ─────────────────────────────────────────────────────────────

    function test_name() public view {
        assertEq(token.name(), "DeFi Governance Token");
    }

    function test_symbol() public view {
        assertEq(token.symbol(), "DGT");
    }

    function test_decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_maxSupply() public view {
        assertEq(token.MAX_SUPPLY(), MAX_SUPPLY);
    }

    // ─── Initial State ────────────────────────────────────────────────────────

    function test_initialSupplyMintedToOwner() public view {
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    function test_totalSupplyEqualsInitialSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function test_ownerIsCorrect() public view {
        assertEq(token.owner(), owner);
    }

    // ─── Mint ─────────────────────────────────────────────────────────────────

    function test_mint_ownerCanMint() public {
        vm.prank(owner);
        token.mint(alice, 500e18);
        assertEq(token.balanceOf(alice), 500e18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + 500e18);
    }

    function test_mint_emitsMintedEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit DeFiToken.Minted(alice, 500e18);
        token.mint(alice, 500e18);
    }

    function test_mint_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 500e18);
    }

    function test_mint_revertsIfExceedsMaxSupply() public {
        uint256 remaining = MAX_SUPPLY - INITIAL_SUPPLY;
        vm.prank(owner);
        vm.expectRevert();
        token.mint(alice, remaining + 1);
    }

    function test_mint_canMintUpToMaxSupply() public {
        uint256 remaining = MAX_SUPPLY - INITIAL_SUPPLY;
        vm.prank(owner);
        token.mint(alice, remaining);
        assertEq(token.totalSupply(), MAX_SUPPLY);
    }

    function test_mint_revertsIfInitialExceedsMax() public {
        vm.prank(owner);
        vm.expectRevert();
        new DeFiToken(owner, MAX_SUPPLY + 1);
    }

    // ─── Transfer ─────────────────────────────────────────────────────────────

    function test_transfer_succeeds() public {
        vm.prank(owner);
        token.transfer(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 100e18);
    }

    function test_transferFrom_withApproval() public {
        vm.prank(owner);
        token.approve(alice, 100e18);
        vm.prank(alice);
        token.transferFrom(owner, bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    // ─── Delegation ───────────────────────────────────────────────────────────

    function test_delegate_toSelf_grantsVotingPower() public {
        vm.prank(owner);
        token.delegate(owner);
        assertEq(token.getVotes(owner), INITIAL_SUPPLY);
    }

    function test_delegateToSelf_helper() public {
        vm.prank(owner);
        token.delegateToSelf();
        assertEq(token.getVotes(owner), INITIAL_SUPPLY);
    }

    function test_delegate_toOther_transfersVotingPower() public {
        vm.prank(owner);
        token.delegate(alice);
        assertEq(token.getVotes(alice), INITIAL_SUPPLY);
        assertEq(token.getVotes(owner), 0);
    }

    function test_undelegated_hasNoVotingPower() public view {
        // Without delegation, votes are zero even with tokens
        assertEq(token.getVotes(owner), 0);
    }

    function test_delegate_transferViaTransfer() public {
        vm.prank(owner);
        token.delegate(owner);

        vm.prank(owner);
        token.transfer(alice, 100e18);

        // Alice has no delegate yet, so her received tokens have no voting power
        assertEq(token.getVotes(owner), INITIAL_SUPPLY - 100e18);
        assertEq(token.getVotes(alice), 0);
    }

    function test_delegate_aliceDelegatesAfterReceive() public {
        vm.prank(owner);
        token.transfer(alice, 100e18);

        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 100e18);
    }

    // ─── Voting Power Snapshots ───────────────────────────────────────────────

    function test_getPastVotes_snapshotsAtBlock() public {
        vm.prank(owner);
        token.delegate(owner);

        uint256 snapBlock = block.number;
        vm.roll(block.number + 1);

        // Mint after the snapshot block
        vm.prank(owner);
        token.mint(alice, 1000e18);

        // getPastVotes returns power at the snapshot block
        assertEq(token.getPastVotes(owner, snapBlock), INITIAL_SUPPLY);
    }

    function test_getPastTotalSupply_afterMint() public {
        uint256 snapBlock = block.number;
        vm.roll(block.number + 1);

        vm.prank(owner);
        token.mint(alice, 1000e18);

        assertEq(token.getPastTotalSupply(snapBlock), INITIAL_SUPPLY);
    }

    // ─── Permit (ERC20Permit) ─────────────────────────────────────────────────

    function test_permit_works() public {
        uint256 privKey = 0xA11CE;
        address signer = vm.addr(privKey);

        // Fund the signer
        vm.prank(owner);
        token.transfer(signer, 1000e18);

        uint256 nonceBefore = token.nonces(signer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                bob,
                500e18,
                nonceBefore,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);

        token.permit(signer, bob, 500e18, deadline, v, r, s);

        assertEq(token.allowance(signer, bob), 500e18);
        assertEq(token.nonces(signer), nonceBefore + 1);
    }

    function test_permit_revertsExpiredDeadline() public {
        uint256 privKey = 0xB0B;
        address signer = vm.addr(privKey);
        uint256 deadline = block.timestamp - 1; // already expired

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, bytes32(0));
        vm.expectRevert();
        token.permit(signer, alice, 1, deadline, v, r, s);
    }

    // ─── Nonces ───────────────────────────────────────────────────────────────

    function test_nonces_startAtZero() public view {
        assertEq(token.nonces(owner), 0);
    }
}
