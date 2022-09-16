pragma solidity 0.5.8;

contract blockGasLimit {
    uint256[1] _blockGasLimit = [
        40000000 //default block gas limit
    ];
    function getBlockGasLimit() public view returns (uint32[1] memory) {
        return _blockGasLimit;
    }
}
