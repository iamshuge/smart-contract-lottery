// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

/**
 * @title a sample Raffle Contract
 * @author 0xNov1ce
 * @notice Raffle
 */

contract Raffle is VRFConsumerBaseV2{

    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance, 
        uint256 numPlayers, 
        RaffleState raffleState
    );

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDs = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;


    address payable[] private s_players; 
    uint256 private s_lastTimeStamp;
    address private s_recent_Winner;
    RaffleState private s_raffleState;

    event EnterRaffle(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);
    
    constructor(
        uint256 entranceFee, 
        uint256 interval, 
        address vrfCoordinator, 
        bytes32 gasLane, 
        uint64 subscriptionId,
        uint32 callbackGasLimit
    )VRFConsumerBaseV2(vrfCoordinator){
        i_entranceFee = entranceFee;
        i_interval = interval; 
        // 接口这里需要传入一个地址再做强制类型转换
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not enough Eth sent");
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }

        if (s_raffleState != RaffleState.OPEN){
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));

        emit EnterRaffle(msg.sender);

    }

    // 调用checkUpkeep的几个条件：
    // 1.时间间隔满足要求
    // 2.raffle是开启状态
    // 3.有人参加（合约里有ETH）
    // 4.chainlink的订阅开启
    function checkUpkeep( 
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp >= i_interval);
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool hasBalance = (address(this).balance > 0);
        bool hasPlayers =  (s_players.length > 0);
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);

        return (upkeepNeeded,"0x0");
    }


    function performUpkeep(bytes calldata /* performData */) external {

        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded){
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                s_raffleState
            );
        }

        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // GAS lane
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDs
        );
        emit RequestedRaffleWinner(requestId);
    }

    // chainlink接受响应后，会调用下面这个函数进行响应，从而获得随机数
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override{
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recent_Winner = winner;

        s_raffleState = RaffleState.OPEN;
        // 重置数组
        s_players = new address payable[](0); 
        s_lastTimeStamp = block.timestamp;

        emit WinnerPicked(winner);

        (bool success, ) = winner.call{value:address(this).balance}("");
        if (!success){
            revert Raffle__TransferFailed();
        }

    }


    function getEntranceFee() external view returns(uint256){
        return i_entranceFee;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() public view returns (address) {
        return s_recent_Winner;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

}