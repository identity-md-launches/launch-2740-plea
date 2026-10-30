// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PLEA} from "../src/PLEA.sol";

/// @dev A closed set of holders with an independent balance and allowance accounting model.
contract PLEAHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    PLEA public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(PLEA token_) {
        token = token_;
        actors[0] = makeAddr("holder zero");
        actors[1] = makeAddr("holder one");
        actors[2] = makeAddr("holder two");
        actors[3] = makeAddr("holder three");
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function transferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 amount = _edgeAmount(amountSeed, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    /// @dev Raw approvals above deliberately cover all 256 bits. This action also makes small,
    /// revoked, infinite, and nearly infinite approvals frequent in the random sequences.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256[6] memory amounts =
            [uint256(0), 1, SUPPLY, SUPPLY + 1, type(uint256).max - 1, type(uint256).max];
        _approve(
            actors[ownerSeed % 4], actors[spenderSeed % 4], amounts[amountSeed % amounts.length]
        );
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        _approve(owner, spender, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, 1);
        // No ghost update on a rejected spend: both global models must remain intact.
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 excessSeed) external {
        address from = actors[fromSeed % 4];
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excessSeed, 1, type(uint256).max - balance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount
            )
        );
        vm.prank(from);
        token.transfer(actors[toSeed % 4], amount);
    }

    function transferFromOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed)
        external
    {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed == type(uint256).max) {
            // An infinite allowance cannot be exceeded; explicitly replace it with a finite one.
            allowed = expectedBalance[owner];
            _approve(owner, spender, allowed);
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, actors[toSeed % 4], allowed + 1);
    }

    function transferFromOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + 1;
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, actors[toSeed % 4], amount);
        // This failure occurs after allowance spending. The original approval must survive.
    }

    function transferToZero(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 amountSeed,
        bool delegated
    ) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 limit = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < limit) {
            limit = expectedAllowance[owner][spender];
        }
        uint256 amount = _edgeAmount(amountSeed, limit);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        vm.prank(actors[ownerSeed % 4]);
        token.approve(address(0), amount);
    }

    /// @dev A valid holder must always be able to move its entire balance, even after failures.
    function transferEntireBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _edgeAmount(uint256 seed, uint256 limit) internal pure returns (uint256) {
        uint256 choice = seed % 5;
        if (choice == 0) return 0;
        if (choice == 1) return limit == 0 ? 0 : 1;
        if (choice == 2) return limit;
        if (choice == 3) return limit == 0 ? 0 : limit - 1;
        return bound(seed, 0, limit);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PLEAInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    PLEA internal token;
    PLEAHandler internal handler;

    function setUp() public {
        token = new PLEA();
        handler = new PLEAHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        // Start with multiple funded owners and both finite and infinite approvals, so delegated
        // transfers can move value immediately instead of waiting for matching random approvals.
        for (uint256 i = 1; i < 4; ++i) {
            handler.transfer(0, i, SUPPLY / 4);
        }
        handler.approve(0, 1, SUPPLY / 4);
        handler.approve(1, 2, type(uint256).max);
        handler.approve(2, 3, SUPPLY / 4);
        handler.approve(3, 0, type(uint256).max);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = PLEAHandler.transfer.selector;
        selectors[1] = PLEAHandler.approve.selector;
        selectors[2] = PLEAHandler.transferFrom.selector;
        selectors[3] = PLEAHandler.approveBoundary.selector;
        selectors[4] = PLEAHandler.revokeAndAttemptSpend.selector;
        selectors[5] = PLEAHandler.transferOverBalance.selector;
        selectors[6] = PLEAHandler.transferFromOverAllowance.selector;
        selectors[7] = PLEAHandler.transferFromOverBalance.selector;
        selectors[8] = PLEAHandler.transferToZero.selector;
        selectors[9] = PLEAHandler.approveZeroSpender.selector;
        selectors[10] = PLEAHandler.transferEntireBalance.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariantSupplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariantAllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariantMetadataIsStable() public view {
        assertEq(token.name(), "PLEA");
        assertEq(token.symbol(), "PLEA");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// @dev Check liveness from every final random state, including states reached after failures.
    function afterInvariant() public {
        for (uint256 i = 1; i < 4; ++i) {
            handler.transferEntireBalance(i, 0);
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        invariantSupplyAndBalancesMatchModel();
        invariantAllowancesMatchModel();
    }
}
