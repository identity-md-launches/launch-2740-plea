// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PLEA} from "../src/PLEA.sol";

/// forge-config: default.fuzz.runs = 1000
contract PLEAEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    PLEA internal token;
    address internal alice;
    address internal bob;
    address internal spender;
    address internal otherSpender;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function setUp() public {
        token = new PLEA();
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
        otherSpender = makeAddr("edge other spender");
    }

    function testOneWeiAllowanceCannotBeSpentTwice() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testLargestFiniteAllowanceIsConsumed() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumTransferAmountRevertsWithoutOverflowOrAllowanceLoss() public {
        uint256 amount = type(uint256).max;
        bytes memory reason = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount
        );
        vm.expectRevert(reason);
        token.transfer(alice, amount);
        assertTrue(token.approve(spender, amount));
        vm.expectRevert(reason);
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testHolderTransferFromRequiresItsOwnAllowance() public {
        assertTrue(token.transfer(alice, 2));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1)
        );
        vm.prank(alice);
        token.transferFrom(alice, alice, 1);
        assertEq(token.balanceOf(alice), 2);

        vm.prank(alice);
        assertTrue(token.approve(alice, 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, alice, 1));
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.allowance(alice, alice), 0);
        // Ordinary transfer remains usable without a self-approval.
        vm.prank(alice);
        assertTrue(token.transfer(bob, 2));
        assertEq(token.balanceOf(bob), 2);
    }

    function testSpenderCanBeRecipientWithoutReceivingAnExtraCredit() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, SUPPLY));
        assertEq(token.balanceOf(spender), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroApprovalStillRejectsZeroSpender() public {
        assertTrue(token.approve(spender, 9));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 9);
    }

    function testZeroDelegatedSelfTransferPreservesFiniteApproval() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 7));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, alice, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 0));
        assertEq(token.allowance(alice, spender), 7);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testDelegatedSelfTransferWithInsufficientBalanceRestoresAllowance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2)
        );
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInfiniteApprovalCanBeReducedThenRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testApprovalDoesNotAuthorizeADifferentSpenderOrOwner() public {
        assertTrue(token.transfer(alice, 10));
        assertTrue(token.transfer(bob, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1
            )
        );
        vm.prank(otherSpender);
        token.transferFrom(alice, otherSpender, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(bob, spender, 1);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 10);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.allowance(alice, spender), 10);
    }

    function testFuzzSpentAllowanceReplacementIsExactAndIsolated(
        uint256 initial,
        uint256 replacement,
        uint256 spendSeed
    ) public {
        uint256 limit = initial < SUPPLY ? initial : SUPPLY;
        uint256 spent = bound(spendSeed, 0, limit);
        assertTrue(token.approve(spender, initial));
        assertTrue(token.approve(otherSpender, 17));
        vm.prank(alice);
        assertTrue(token.approve(spender, 23));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, spent));
        assertEq(
            token.allowance(address(this), spender),
            initial == type(uint256).max ? initial : initial - spent
        );

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), otherSpender), 17);
        assertEq(token.allowance(alice, spender), 23);
        assertEq(token.balanceOf(bob), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzFailedDelegatedTransferPreservesLargeApproval(
        uint256 balanceSeed,
        uint256 amountSeed,
        uint256 approvalSeed
    ) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        uint256 approved = bound(approvalSeed, amount, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSplitDelegatedTransfersEqualOneSpend(
        uint256 amountSeed,
        uint256 splitSeed,
        uint256 approvalSeed
    ) public {
        PLEA single = new PLEA();
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 first = bound(splitSeed, 0, amount);
        uint256 approved = bound(approvalSeed, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        assertTrue(single.approve(spender, approved));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, amount - first));
        assertTrue(single.transferFrom(address(this), alice, amount));
        vm.stopPrank();
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        // Anchor the metamorphic comparison to the requested quantities as well.
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(
            token.allowance(address(this), spender),
            approved == type(uint256).max ? approved : approved - amount
        );
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzzRepeatedRoundTripsCannotCreateOrDestroyDust(
        uint256 balanceSeed,
        uint256 amountSeed,
        uint8 cycleSeed
    ) public {
        uint256 aliceBalance = bound(balanceSeed, 0, SUPPLY);
        uint256 bobBalance = SUPPLY - aliceBalance;
        uint256 amount = bound(amountSeed, 0, aliceBalance);
        uint256 cycles = bound(cycleSeed, 1, 8);
        assertTrue(token.transfer(alice, aliceBalance));
        assertTrue(token.transfer(bob, bobBalance));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(bob);
        assertTrue(token.approve(spender, 1));
        for (uint256 i; i < cycles; ++i) {
            vm.prank(alice);
            assertTrue(token.transfer(bob, amount));
            assertEq(token.balanceOf(alice), aliceBalance - amount);
            assertEq(token.balanceOf(bob), bobBalance + amount);
            vm.prank(bob);
            assertTrue(token.transfer(alice, amount));
            assertEq(token.balanceOf(alice), aliceBalance);
            assertEq(token.balanceOf(bob), bobBalance);
            assertEq(token.totalSupply(), SUPPLY);
        }
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.allowance(bob, spender), 1);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(spender), 0);
    }
}
