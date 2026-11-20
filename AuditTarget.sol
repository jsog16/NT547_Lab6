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
    address payable internal treasury;

    event Deposited(address indexed who, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
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
        to.call{value: address(this).balance}("");
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
        for (uint256 i = 0; i < receivers.length; i++) {
            stakes[receivers[i]] += msg.value;
        }
    }

    function zeroBalance() external view returns (bool) {
        return address(this).balance == 0;
    }

    function handOver(address newOwner) external {
        require(tx.origin == owner, "not owner");
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }
}
