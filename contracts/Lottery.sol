// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title SimpleLottery
 * @dev A simple lottery contract designed to compile with Solidity 0.8.24 (compiler24).
 * Features:
 *  - Owner-managed lottery lifecycle (open/close)
 *  - Players can join by sending exactly ticketPrice per ticket
 *  - Multiple tickets per address allowed
 *  - Owner can pick a winner (pseudo-random) and distribute prize
 *  - Owner receives a configurable fee (in basis points)
 *  - Emergency withdrawal for owner
 *
 * SECURITY NOTE:
 *  - This contract uses pseudo-randomness derived from block variables. That is
 *    NOT secure for high-value lotteries. For production use, integrate a
 *    verifiable randomness source such as Chainlink VRF.
 *
 */
contract SimpleLottery {
    address public owner;
    address[] private players;
    uint256 public ticketPrice; // price per ticket in wei
    bool public isOpen;
    uint16 public ownerFeeBps; // owner fee in basis points (1 bps = 0.01%)

    // Track tickets per player (optional bookkeeping)
    mapping(address => uint256) public ticketsBought;

    // Events
    event LotteryOpened(uint256 ticketPrice, uint16 ownerFeeBps);
    event LotteryClosed();
    event TicketBought(address indexed buyer, uint256 numTickets);
    event WinnerPicked(address indexed winner, uint256 amountWon);
    event OwnerWithdrawn(address indexed owner, uint256 amount);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier whenOpen() {
        require(isOpen, "Lottery not open");
        _;
    }

    modifier whenClosed() {
        require(!isOpen, "Lottery open");
        _;
    }

    constructor(uint256 _ticketPrice, uint16 _ownerFeeBps) {
        require(_ticketPrice > 0, "Ticket price > 0");
        require(_ownerFeeBps <= 10000, "Fee bps <= 10000");
        owner = msg.sender;
        ticketPrice = _ticketPrice;
        ownerFeeBps = _ownerFeeBps;
        isOpen = false;
    }

    // --- Owner functions ---

    /// @notice Open the lottery so players can buy tickets
    /// @param _ticketPrice price per single ticket (in wei)
    /// @param _ownerFeeBps fee in basis points taken from pot when paying winner
    function openLottery(uint256 _ticketPrice, uint16 _ownerFeeBps) external onlyOwner whenClosed {
        require(_ticketPrice > 0, "Ticket price > 0");
        require(_ownerFeeBps <= 10000, "Fee bps <= 10000");
        ticketPrice = _ticketPrice;
        ownerFeeBps = _ownerFeeBps;
        // reset players/tickets if previous round ended
        delete players;
        // NOTE: mapping `ticketsBought` will remain; not cleared for gas reasons.
        isOpen = true;
        emit LotteryOpened(_ticketPrice, _ownerFeeBps);
    }

    /// @notice Close the lottery to stop ticket sales
    function closeLottery() external onlyOwner whenOpen {
        isOpen = false;
        emit LotteryClosed();
    }

    /// @notice Pick a winner and send the prize. Only owner can call this when lottery is closed.
    /// @dev Uses pseudo-randomness. Not secure for production.
    function pickWinner() external onlyOwner whenClosed {
        require(players.length > 0, "No players");

        uint256 rand = _random();
        uint256 winnerIndex = rand % players.length;
        address payable winner = payable(players[winnerIndex]);

        uint256 pot = address(this).balance;
        require(pot > 0, "Empty pot");

        uint256 ownerFee = (pot * ownerFeeBps) / 10000;
        uint256 winnerAmount = pot - ownerFee;

        // Reset players and ticketsBought (ticketsBought reset is optional - we zero only players' counts for gas reasons)
        for (uint256 i = 0; i < players.length; i++) {
            ticketsBought[players[i]] = 0;
        }
        delete players;

        // Transfer funds
        if (ownerFee > 0) {
            (bool sentOwner, ) = payable(owner).call{value: ownerFee}('');
            require(sentOwner, "Owner fee transfer failed");
        }

        (bool sentWinner, ) = winner.call{value: winnerAmount}('');
        require(sentWinner, "Winner transfer failed");

        emit WinnerPicked(winner, winnerAmount);
    }

    /// @notice Emergency function: owner can withdraw all funds (use only in emergencies)
    function emergencyWithdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "No balance");
        (bool sent, ) = payable(owner).call{value: bal}('');
        require(sent, "Withdraw failed");
        emit OwnerWithdrawn(owner, bal);
    }

    // --- Player functions ---

    /// @notice Buy tickets by sending multiples of ticketPrice
    /// @dev msg.value must be exact multiple of ticketPrice
    function buyTickets() external payable whenOpen {
        require(msg.value >= ticketPrice, "Send at least one ticket price");
        require(msg.value % ticketPrice == 0, "Send multiple of ticketPrice");

        uint256 numTickets = msg.value / ticketPrice;
        for (uint256 i = 0; i < numTickets; i++) {
            players.push(msg.sender);
        }
        ticketsBought[msg.sender] += numTickets;

        emit TicketBought(msg.sender, numTickets);
    }

    /// @notice View number of players (ticket entries)
    function getPlayersCount() external view returns (uint256) {
        return players.length;
    }

    /// @notice Helper to get players (careful - may be expensive if many players)
    function getPlayers() external view returns (address[] memory) {
        return players;
    }

    // --- Internal ---
    /// @dev Pseudo-random generator. DO NOT use for high-value randomness.
    function _random() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, players)));
    }

    // Accept plain ETH transfers (treated as buyTickets)
    receive() external payable {
        if (isOpen) {
            // Allow only exact multiples of ticketPrice via receive
            require(msg.value >= ticketPrice, "Send at least one ticket price");
            require(msg.value % ticketPrice == 0, "Send multiple of ticketPrice");

            uint256 numTickets = msg.value / ticketPrice;
            for (uint256 i = 0; i < numTickets; i++) {
                players.push(msg.sender);
            }
            ticketsBought[msg.sender] += numTickets;
            emit TicketBought(msg.sender, numTickets);
        } else {
            // If closed, reject direct transfers to avoid locking funds unexpectedly
            revert("Lottery closed");
        }
    }

    fallback() external payable {
        // forward to receive
        revert("Use buyTickets or send exact multiples of ticketPrice when open");
    }
}
