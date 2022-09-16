pragma solidity 0.5.8;

contract transactionFeeRates {
    uint64[3] _transactionFeeRates = [
        10E8, //0: minRelayTxFee
        10E8, //1: incrementalRelayFee
        30E8  //2: dustRelayFee
    ];
    function getTransactionFeeRates() public view returns (uint256[3] memory) {
        return _transactionFeeRates;
    }
}
