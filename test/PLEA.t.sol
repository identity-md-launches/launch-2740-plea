// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PLEA} from "../src/PLEA.sol";

contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (PLEA) {
        return new PLEA{salt: salt}();
    }
}

contract PLEATest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    PLEA internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new PLEA();
    }

    function testMetadataAndEntireSupply() public view {
        assertEq(token.name(), "PLEA");
        assertEq(token.symbol(), "PLEA");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        PLEA fresh = new PLEA();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function testCreate2FactoryReceivesEntireSupply() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        vm.prank(alice);
        PLEA fresh = factory.deploy(keccak256("PLEA factory deployment test"));

        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
        assertEq(fresh.balanceOf(address(fresh)), 0);
    }

    function testTransferReturnsTrueAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 42 ether);
        assertTrue(token.transfer(alice, 42 ether));

        assertEq(token.balanceOf(address(this)), SUPPLY - 42 ether);
        assertEq(token.balanceOf(alice), 42 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testEntireSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferToContractRequiresNoReceiverCallback() public {
        TokenFactoryFixture recipient = new TokenFactoryFixture();
        assertTrue(token.transfer(address(recipient), 7 ether));
        assertEq(token.balanceOf(address(recipient)), 7 ether);
    }

    function testRevertTransferWithInsufficientBalanceIsAtomic() public {
        assertTrue(token.transfer(alice, 1 ether));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, 1 ether + 1
            )
        );
        vm.prank(alice);
        token.transfer(bob, 1 ether + 1);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testRevertSelfTransferStillRequiresBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function testRevertTransferToZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testRevertZeroTransferToZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 0);
    }

    function testApproveReturnsTrueAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 50 ether);
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testApprovalCanBeReplacedAndRevoked() public {
        assertTrue(token.approve(spender, 50 ether));
        assertTrue(token.approve(spender, 7 ether));
        assertEq(token.allowance(address(this), spender), 7 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testApprovalDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function testApprovalBelongsOnlyToCaller() public {
        assertTrue(token.approve(spender, 7 ether));
        vm.prank(alice);
        assertTrue(token.approve(spender, 3 ether));
        assertEq(token.allowance(address(this), spender), 7 ether);
        assertEq(token.allowance(alice, spender), 3 ether);
        assertEq(token.allowance(bob, spender), 0);
    }

    function testRevertApproveZeroSpender() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function testTransferFromSpendsAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 50 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 20 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 20 ether));

        assertEq(token.allowance(address(this), spender), 30 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
        assertEq(token.balanceOf(alice), 20 ether);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testExactAllowanceCanBeExhausted() public {
        assertTrue(token.approve(spender, 1 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1 ether));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    function testInfiniteAllowanceRemainsUnchanged() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1 ether));
        assertTrue(token.transferFrom(address(this), bob, 2 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 2 ether);
    }

    function testZeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testTransferFromToSelfSpendsAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(spender, 1 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 1 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testRevertTransferFromWithoutApproval() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function testRevertDeployerCannotSpendHolderBalanceWithoutApproval() public {
        assertTrue(token.transfer(alice, 2 ether));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1 ether
            )
        );
        token.transferFrom(alice, address(this), 1 ether);
        assertEq(token.balanceOf(alice), 2 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 2 ether));
        assertEq(token.balanceOf(bob), 2 ether);
    }

    function testRevertTransferFromAboveAllowanceIsAtomic() public {
        assertTrue(token.approve(spender, 5 ether));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, 5 ether, 5 ether + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 5 ether + 1);
        assertEq(token.allowance(address(this), spender), 5 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function testRevertTransferFromAboveBalanceRestoresAllowance() public {
        assertTrue(token.transfer(alice, 1 ether));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2 ether));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, 2 ether
            )
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 2 ether);
        assertEq(token.allowance(alice, spender), 2 ether);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function testRevertTransferFromToZeroRestoresAllowance() public {
        assertTrue(token.approve(spender, 1 ether));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 1 ether);
        assertEq(token.allowance(address(this), spender), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testRevertTransferFromZeroEvenForZeroAmount() public {
        // Allowance validation runs before transfer validation in OpenZeppelin ERC20.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0))
        );
        token.transferFrom(address(0), bob, 0);
    }

    function testLaunchDistributionClaimsAndPoolTransfersArriveWhole() public {
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address requester = makeAddr("requester");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY - swarm - pool;

        assertTrue(token.transfer(distributor, swarm));
        assertTrue(token.transfer(poolManager, pool));
        assertTrue(token.transfer(requester, remainder));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.balanceOf(requester), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(alice, swarm));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(alice), swarm);

        vm.prank(poolManager);
        assertTrue(token.transfer(bob, 1 ether));
        assertEq(token.balanceOf(bob), 1 ether);
        vm.prank(bob);
        assertTrue(token.transfer(poolManager, 1 ether));
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testNoMintBurnOrAdministrativeEntryPoints() public {
        assertTrue(token.transfer(alice, 10 ether));
        bytes[] memory calls = new bytes[](14);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[10] = abi.encodeWithSignature("initialize(address)", bob);
        calls[11] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[12] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[13] = abi.encodeWithSignature("owner()");

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 10 ether);
            assertEq(token.balanceOf(bob), 0);
        }

        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function testRejectsNativeCurrency() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromUsesOnlyAuthorizedAmount(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, spent));
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(bob), spent);
        assertEq(token.allowance(address(this), spender), approved - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzRevertAboveBalance(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        assertTrue(token.transfer(alice, balance));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess
            )
        );
        vm.prank(alice);
        token.transfer(bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzRevertAboveAllowance(uint256 approved, uint256 excess) public {
        approved = bound(approved, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - approved);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                spender,
                approved,
                approved + excess
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, approved + excess);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzzTransferToAnyNonzeroRecipient(address recipient, uint256 amount) public {
        recipient = address(uint160(bound(uint160(recipient), 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertEq(token.balanceOf(recipient), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
