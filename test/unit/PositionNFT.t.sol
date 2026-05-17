// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/tokens/PositionNFT.sol";

contract PositionNFTTest is Test {
    PositionNFT nft;

    address lendingPool = makeAddr("lendingPool");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address stranger = makeAddr("stranger");

    function setUp() public {
        vm.prank(lendingPool);
        nft = new PositionNFT(lendingPool);
    }

    // ─── Minting ─────────────────────────────────────────────────────────────

    function test_mint_createsTokenForUser() public {
        vm.prank(lendingPool);
        nft.mint(user1);

        uint256 tokenId = nft.positionOf(user1);
        assertEq(tokenId, 1, "first token id should be 1");
        assertEq(nft.ownerOf(tokenId), user1, "user1 should own the token");
    }

    function test_mint_incrementsTokenId() public {
        vm.prank(lendingPool);
        nft.mint(user1);

        vm.prank(lendingPool);
        nft.mint(user2);

        assertEq(nft.positionOf(user1), 1);
        assertEq(nft.positionOf(user2), 2);
    }

    function test_mint_revertsIfUserAlreadyHasToken() public {
        vm.prank(lendingPool);
        nft.mint(user1);

        vm.prank(lendingPool);
        vm.expectRevert(abi.encodeWithSelector(PositionNFT.AlreadyHasPosition.selector, user1));
        nft.mint(user1);
    }

    function test_mint_revertsIfCallerNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        nft.mint(user1);
    }

    // ─── Burning ─────────────────────────────────────────────────────────────

    function test_burn_removesToken() public {
        vm.prank(lendingPool);
        nft.mint(user1);

        uint256 tokenId = nft.positionOf(user1);

        vm.prank(lendingPool);
        nft.burn(user1);

        assertEq(nft.positionOf(user1), 0, "positionOf should be 0 after burn");
        vm.expectRevert();
        nft.ownerOf(tokenId); // token no longer exists
    }

    function test_burn_revertsIfNoPosition() public {
        vm.prank(lendingPool);
        vm.expectRevert(abi.encodeWithSelector(PositionNFT.NoPosition.selector, user1));
        nft.burn(user1);
    }

    function test_burn_revertsIfCallerNotOwner() public {
        vm.prank(lendingPool);
        nft.mint(user1);

        vm.prank(stranger);
        vm.expectRevert();
        nft.burn(user1);
    }

    function test_burn_allowsRemintAfterBurn() public {
        vm.prank(lendingPool);
        nft.mint(user1);

        vm.prank(lendingPool);
        nft.burn(user1);

        vm.prank(lendingPool);
        nft.mint(user1);

        assertEq(nft.positionOf(user1), 2, "reminted token should have next id");
        assertEq(nft.ownerOf(2), user1);
    }

    // ─── Soulbound: transfers disabled ───────────────────────────────────────

    function test_transferFrom_reverts() public {
        vm.prank(lendingPool);
        nft.mint(user1);

        uint256 tokenId = nft.positionOf(user1);

        vm.prank(user1);
        vm.expectRevert(PositionNFT.Soulbound.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    function test_safeTransferFrom_reverts() public {
        vm.prank(lendingPool);
        nft.mint(user1);

        uint256 tokenId = nft.positionOf(user1);

        vm.prank(user1);
        vm.expectRevert(PositionNFT.Soulbound.selector);
        nft.safeTransferFrom(user1, user2, tokenId, "");
    }

    // ─── Metadata ────────────────────────────────────────────────────────────

    function test_name_and_symbol() public view {
        assertEq(nft.name(), "DeFi Position");
        assertEq(nft.symbol(), "DPOS");
    }
}
