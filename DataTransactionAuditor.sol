// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Counters.sol";

contract DataTransactionAuditor {
    using Counters for Counters.Counter;
    
    struct DataTransaction {
        uint256 id;
        address payable dataBuyer;
        address payable dataSeller;
        address payable mediator;
        uint256 amount;
        uint256 disputeDeadline;
        bool isResolved;
        bytes32 sellerHash;
        bool sellerFlag;
        bytes32 buyerHash;
        bool buyerFlag;
        bool awaitingMediator;
    }

    event TransactionCreated(uint256 indexed transactionId);
    event HashesUpdated(uint256 indexed transactionId);
    event TransactionResolved(uint256 indexed transactionId);
    event Conflict(uint256 indexed transactionId);
    event mediatorNeeded(uint256 indexed transactionId);

    Counters.Counter private _transactionIdTracker;
    mapping(uint256 => DataTransaction) public transactions;

    string public dataQualityCode;
    uint256 public minAmount;
    uint256 public deadlineHours;
    address public mediator;
    address public dataSeller;
    address public dataBuyer;

    constructor(
        string memory _dataQualityCode,
        address _dataSeller,
        address _mediator,
        uint256 _minAmount,
        uint256 _deadlineHours
    ) {
        dataQualityCode = _dataQualityCode;
        dataBuyer = msg.sender;
        dataSeller = _dataSeller;
        mediator = _mediator;
        minAmount = _minAmount;
        deadlineHours = _deadlineHours;
    }


    function createTransaction(
        ) external payable returns (uint256) {
        require(msg.sender == dataBuyer, "Only the buyer may transfer funds to the contract.");
        require(msg.value >= minAmount, "Transaction amount is less than the minimum requirement.");
        uint256 transactionId = _transactionIdTracker.current();
        _transactionIdTracker.increment();

        transactions[transactionId] = DataTransaction({
            id: transactionId,
            dataBuyer: payable(msg.sender),
            dataSeller: payable(dataSeller),
            mediator: payable(mediator),
            amount: msg.value,
            disputeDeadline: 0,
            isResolved: false,
            sellerHash: bytes32(0),
            sellerFlag: false,
            buyerHash: bytes32(0),
            buyerFlag: false,
            awaitingMediator: false
        });

        emit TransactionCreated(transactionId);
        return transactionId;
    }


    function submitHashes(
        uint256 _transactionId,
        bytes32 _codeHash,
        bool _resultFlag
    ) external {
        DataTransaction storage txn = transactions[_transactionId];

        require(!txn.isResolved, "Transaction already resolved.");
        require(txn.dataBuyer == msg.sender || txn.dataSeller == msg.sender, "Only buyer or seller can submit hashes.");
        require(txn.awaitingMediator == false, "Awaiting mediator action.");

        if(txn.disputeDeadline != 0){
            require(txn.sellerHash != bytes32(0) && txn.buyerHash != bytes32(0), "Both parties must submit hashes.");
            require(block.timestamp > txn.disputeDeadline, "Dispute deadline not reached yet.");

            txn.awaitingMediator = true;
            emit mediatorNeeded(_transactionId);
            return;
        }

        // If the dataBuyer calls the function.
        if (msg.sender == txn.dataBuyer) {
            require(txn.sellerHash != bytes32(0), "Seller must submit hash first.");
            txn.buyerHash = _codeHash;
            txn.buyerFlag = _resultFlag;
        }
        // If the dataSeller calls the function.
        else if (msg.sender == txn.dataSeller) {
            txn.sellerHash = _codeHash;
            txn.sellerFlag = _resultFlag;
        }

        // If both buyer and seller have submitted their hashes, check if they match.
        if (txn.buyerHash != bytes32(0) && txn.sellerHash != bytes32(0)) {
            // If the submitted hashes and flags match.
            if (txn.sellerHash == txn.buyerHash && txn.sellerFlag == txn.buyerFlag) {
                if (_resultFlag) {
                    txn.isResolved = true;
                    txn.dataSeller.transfer(txn.amount);
                    emit TransactionResolved(_transactionId);
                } else {
                    txn.isResolved = true;
                    txn.dataBuyer.transfer(txn.amount);
                    emit TransactionResolved(_transactionId);
                }
            } else {
                // If the hashes do not match, start timer, emit
                if (txn.disputeDeadline == 0) {
                    txn.disputeDeadline = block.timestamp + deadlineHours * 1 hours;
                    emit Conflict(_transactionId);
        }
            }
        }

        emit HashesUpdated(_transactionId);
    }


    function mediatorSubmitHashes(
        uint256 _transactionId,
        bytes32 _codeHash,
        bool _resultFlag
    ) external {
        DataTransaction storage txn = transactions[_transactionId];
        require(txn.mediator == msg.sender, "Only mediator can submit hashes.");
        require(txn.awaitingMediator, "Mediator not allowed yet.");

        if ((txn.sellerHash == _codeHash && txn.sellerFlag == _resultFlag) || 
            (txn.buyerHash == _codeHash && txn.buyerFlag == _resultFlag)) {
            txn.isResolved = true;
            if (_resultFlag) {
                txn.dataSeller.transfer(txn.amount);
            } else {
                txn.dataBuyer.transfer(txn.amount);
            }
            emit TransactionResolved(_transactionId);
        }
    }

    function getCode() external view returns (string memory) {
        return dataQualityCode;
    }
}
