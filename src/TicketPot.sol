// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title TicketPot - no-loss prize pool in native BOT.
/// Deposit BOT, keep your principal (withdraw any time), win prizes funded by sponsors.
/// Weekly draw: commit (hash + bond) -> wait -> reveal. Winner chosen by deposit-weighted sortition.
/// No owner, no admin, no upgrade. Treasury address is immutable and only earns the sponsor fee.
contract TicketPot {
    // ------------------------------------------------------------- config
    uint256 public constant MIN_DEPOSIT = 0.01 ether;
    uint256 public constant SPONSOR_FEE_BPS = 500;   // 5% of sponsored prizes
    uint256 public constant KEEPER_BPS = 100;        // 1% of the pot to whoever reveals
    uint256 public constant BOND_BPS = 1000;         // commit bond = 10% of pot ...
    uint256 public constant MIN_BOND = 0.05 ether;   // ... at least this much
    uint256 public constant REVEAL_DELAY = 10;       // blocks between commit and the block whose hash seeds the draw
    uint256 public constant REVEAL_WINDOW = 200;     // reveal must land within this many blocks of the commit
    uint256 public constant MAX_USERS = 65535;
    uint256 private constant BPS = 10_000;

    uint256 public immutable roundLength;
    uint256 public immutable startTime;
    address public immutable treasury;
    uint256 public immutable drawGrace;           // delay after a round turns before a draw may be committed, so keepers can sync everyone

    // ------------------------------------------------------------- state
    struct User {
        uint16 slot;          // 1-based index in the sortition tree, 0 = never deposited
        uint64 freshRound;    // round in which `fresh` was deposited
        uint256 eligible;     // principal counted in the tree
        uint256 fresh;        // principal deposited in `freshRound`, not yet eligible
        uint256 pendingCut;   // eligible weight still in the tree because the user withdrew during a lock
    }
    mapping(address => User) public users;
    address[] public slotOwner;                   // slotOwner[slot-1]
    mapping(uint256 => uint256) private _tree;    // Fenwick tree over eligible weight
    uint256 public treeTotal;                     // sum of tree weights (includes pending cuts)
    uint256 public totalPendingCut;

    uint256 public totalPrincipal;
    uint256 public pot;                           // prize pot
    uint256 public bondsHeld;
    mapping(address => uint256) public owed;      // prizes, keeper rewards, fees (pull)
    uint256 public totalOwed;

    uint256 public lastDrawRound = 1;             // round in which the last draw was committed (1 = none yet, first draw in round 2)
    uint256 public drawCount;
    struct Commit { address committer; bytes32 hash; uint64 block; uint64 round; uint256 bond; uint256 prize; }
    Commit public commitment;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Sponsored(address indexed sponsor, uint256 amount, uint256 fee);
    event Committed(address indexed committer, uint256 round, uint256 bond, uint256 prize);
    event DrawResult(uint256 indexed draw, address indexed winner, uint256 prize, uint256 keeperReward);
    event CommitSlashed(address indexed committer, uint256 bond);
    event PrizeClaimed(address indexed user, uint256 amount);

    error BadParam(); error TooEarly(); error TooLate(); error WrongState(); error Nothing(); error Failed(); error Full();
    uint256 private _lock = 1;
    modifier nonReentrant() { if (_lock != 1) revert Failed(); _lock = 2; _; _lock = 1; }

    constructor(uint256 _roundLength, address _treasury) {
        if (_roundLength < 1 hours || _treasury == address(0)) revert BadParam();
        roundLength = _roundLength; drawGrace = _roundLength / 24; treasury = _treasury; startTime = block.timestamp;
    }

    // ------------------------------------------------------------- views
    function currentRound() public view returns (uint256) { return (block.timestamp - startTime) / roundLength + 1; }
    function locked() public view returns (bool) { return commitment.committer != address(0); }
    function balanceOf(address u) public view returns (uint256) { return users[u].eligible + users[u].fresh; }
    function userCount() external view returns (uint256) { return slotOwner.length; }
    function nextDrawTime() external view returns (uint256) { return startTime + roundLength * lastDrawRound + drawGrace; }
    function bondRequired() public view returns (uint256) { uint256 b = pot * BOND_BPS / BPS; return b < MIN_BOND ? MIN_BOND : b; }
    /// Weight that will count if a draw were committed now (pending cuts are not subtracted until applied).
    function weightOf(address u) external view returns (uint256) { return users[u].eligible; }

    // ------------------------------------------------------------- deposits
    function deposit() external payable {
        if (msg.value < MIN_DEPOSIT) revert BadParam();
        User storage u = users[msg.sender];
        if (u.slot == 0) {
            if (slotOwner.length >= MAX_USERS) revert Full();
            slotOwner.push(msg.sender); u.slot = uint16(slotOwner.length);
        }
        _sync(msg.sender);
        u.fresh += msg.value; u.freshRound = uint64(currentRound());
        totalPrincipal += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// Withdraw principal. Always allowed, including during a draw lock.
    function withdraw(uint256 amount) external nonReentrant {
        User storage u = users[msg.sender];
        if (amount == 0 || amount > u.eligible + u.fresh) revert BadParam();
        _sync(msg.sender);
        uint256 fromFresh = amount > u.fresh ? u.fresh : amount;
        u.fresh -= fromFresh;
        uint256 fromEligible = amount - fromFresh;
        if (fromEligible > 0) {
            u.eligible -= fromEligible;
            if (locked()) { u.pendingCut += fromEligible; totalPendingCut += fromEligible; }
            else _treeAdd(u.slot, fromEligible, false);
        }
        totalPrincipal -= amount;
        emit Withdrawn(msg.sender, amount);
        _send(msg.sender, amount);
    }

    /// Permissionless: move deposits from earlier rounds into the draw and apply deferred exits. No-op while locked.
    function sync(address[] calldata who) external {
        for (uint256 i; i < who.length; i++) _sync(who[i]);
    }

    function _sync(address a) internal {
        if (locked()) return;
        User storage u = users[a];
        if (u.pendingCut > 0) { _treeAdd(u.slot, u.pendingCut, false); totalPendingCut -= u.pendingCut; u.pendingCut = 0; }
        if (u.fresh > 0 && u.freshRound < currentRound()) { u.eligible += u.fresh; _treeAdd(u.slot, u.fresh, true); u.fresh = 0; }
    }

    // ------------------------------------------------------------- prizes
    function sponsor() external payable {
        if (msg.value == 0) revert BadParam();
        uint256 fee = msg.value * SPONSOR_FEE_BPS / BPS;
        owed[treasury] += fee; totalOwed += fee; pot += msg.value - fee;
        emit Sponsored(msg.sender, msg.value, fee);
    }
    receive() external payable { if (msg.value > 0) { pot += msg.value; } } // plain transfers are donations to the pot, no fee

    function claim() external nonReentrant {
        uint256 amt = owed[msg.sender];
        if (amt == 0) revert Nothing();
        owed[msg.sender] = 0; totalOwed -= amt;
        emit PrizeClaimed(msg.sender, amt);
        _send(msg.sender, amt);
    }

    // ------------------------------------------------------------- draw
    /// hash = keccak256(abi.encode(secret, msg.sender)). The committer must reveal 10..200 blocks later or lose the bond to the pot.
    function commitDraw(bytes32 hash) external payable {
        if (locked()) revert WrongState();
        uint256 round = currentRound();
        if (round <= lastDrawRound || block.timestamp < startTime + (round - 1) * roundLength + drawGrace) revert TooEarly();
        if (totalPendingCut != 0 || treeTotal == 0 || pot == 0) revert WrongState();
        uint256 need = bondRequired();
        if (msg.value < need) revert BadParam();
        commitment = Commit(msg.sender, hash, uint64(block.number), uint64(round), msg.value, pot);
        bondsHeld += msg.value;
        emit Committed(msg.sender, round, msg.value, pot);
    }

    function revealDraw(bytes32 secret) external nonReentrant {
        Commit memory c = commitment;
        if (c.committer == address(0) || msg.sender != c.committer) revert WrongState();
        if (keccak256(abi.encode(secret, msg.sender)) != c.hash) revert BadParam();
        if (block.number <= c.block + REVEAL_DELAY) revert TooEarly();
        if (block.number > c.block + REVEAL_WINDOW) revert TooLate();
        bytes32 seed = keccak256(abi.encode(secret, blockhash(c.block + REVEAL_DELAY)));
        address winner = slotOwner[_findSlot(uint256(seed) % treeTotal) - 1];

        delete commitment;
        bondsHeld -= c.bond;
        lastDrawRound = c.round; drawCount++;
        uint256 prize = pot; pot = 0;
        uint256 reward = prize * KEEPER_BPS / BPS;
        uint256 win = prize - reward;
        owed[winner] += win; owed[msg.sender] += reward; totalOwed += prize;
        emit DrawResult(drawCount, winner, win, reward);
        _send(msg.sender, c.bond); // bond back (a failed send reverts the reveal; committer is the caller so that is their own risk)
    }

    /// Committer vanished or revealed too late: bond joins the pot, anyone may commit again.
    function slashCommit() external {
        Commit memory c = commitment;
        if (c.committer == address(0)) revert WrongState();
        if (block.number <= c.block + REVEAL_WINDOW) revert TooEarly();
        delete commitment;
        bondsHeld -= c.bond; pot += c.bond;
        emit CommitSlashed(c.committer, c.bond);
    }

    // ------------------------------------------------------------- Fenwick tree
    function _treeAdd(uint256 slot, uint256 amt, bool add) internal {
        if (add) treeTotal += amt; else treeTotal -= amt;
        for (uint256 i = slot; i <= 65536; i += i & (~i + 1)) {
            if (add) _tree[i] += amt; else _tree[i] -= amt;
        }
    }
    /// Smallest slot whose prefix sum exceeds r (r < treeTotal).
    function _findSlot(uint256 r) internal view returns (uint256 pos) {
        for (uint256 step = 32768; step > 0; step >>= 1) {
            uint256 nxt = pos + step;
            if (nxt <= 65535 && _tree[nxt] <= r) { pos = nxt; r -= _tree[nxt]; }
        }
        return pos + 1;
    }

    function _send(address to, uint256 amt) private { (bool ok, ) = to.call{value: amt}(""); if (!ok) revert Failed(); }
}
