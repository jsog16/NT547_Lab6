// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// NT547 - Lab 06 - Hop dong rieng cua MSSV 25520523. KHONG deploy len mainnet.

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract StakingPool_0523 {
    address public owner;
    mapping(address => uint256) public stakes;
    uint256 public nextRelease;
    address payable internal immutable treasury;

    event Deposited(address indexed who, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address payable _treasury) {
        owner = msg.sender;
	require(_treasury != address(0), "zero");
	treasury = _treasury;
    }

    function stake() external payable {
        stakes[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function ownerWithdraw(uint256 amount) external onlyOwner {
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "withdraw failed");
    }

    function drainTo(address payable to) external onlyOwner {
        require(to != address(0), "zero");
        (bool ok, ) = to.call{value: address(this).balance}("");
	require(ok, "drain failed");
    }

    function releaseTenth() external onlyOwner {
        require(block.timestamp >= nextRelease, "locked");
        nextRelease = block.timestamp + 1 days;
        (bool ok, ) = payable(owner).call{value: address(this).balance / 10}("");
        require(ok, "release failed");
    }

    function payTreasury() external onlyOwner {
        treasury.transfer(address(this).balance / 2);
    }

    function multiFund(address[] calldata receivers) external payable {
	uint256 n = receivers.length;
	require(n > 0, "no receivers");
	require(msg.value % n == 0, "unbalance funds");
	uint256 share = msg.value / n;
        for (uint256 i = 0; i < receivers.length; i++) {
            stakes[receivers[i]] += share;
        }
    }

    function zeroBalance() external view returns (bool) {
	// slither-disable-next-line incorrect-equality
        return address(this).balance == 0;
    }

    function handOver(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }
}
