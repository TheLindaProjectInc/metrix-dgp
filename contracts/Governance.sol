// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

// interfaces
interface DGPInterface {
    function getGovernanceCollateral()
        external
        view
        returns (uint256[1] memory);
}

contract Governance {
    // dgp
    address payable private _dgpAddress =
        payable(address(0x0000000000000000000000000000000000000088));

    address payable private _budgetAddress =
        payable(address(0x0000000000000000000000000000000000000090));

    // governors
    struct Governor {
        uint256 blockHeight; // enrollment block height
        uint256 lastPing; // last ping block
        uint256 collateral; // contract held collateral
        uint256 lastReward; // last block governor was rewarded
        uint16 addressIndex; // position in the address index array
    }

    uint16 private _governorCount = 0; // store the current number of governors
    uint16 private _maximumGovernors = 1920; // how many governors can exist
    uint16 private _blockBeforeMatureGovernor = 15; // blocks to pass before governor is mature
    uint16 private _pingBlockInterval = 30 * 960; // maximum blocks between pings before governor can be removed for being inactive
    uint16 private _blockBeforeGovernorVote = 28 * 960; // blocks to pass before governor is allowed to vote on DGP and budget
    mapping(address => Governor) public governors; // store governor details
    address[] governorAddresses; // store governor address in array for looping
    uint16 _inactiveGovernorIndex = 0;

    // rewards
    uint16 private _rewardBlockInterval = 1920; // how often governors are rewarded. At minimum it should be the size of _maximumGovernors
    uint256 private _lastRewardBlock = 0; // only allow reward to be paid once per block

    // ------------------------------
    // ----- GOVERNANCE SYSTEM ------
    // ------------------------------

    // get total governor funds
    function balance() public view returns (uint256) {
        return address(this).balance;
    }

    // get required governor collateral
    function getRequiredCollateral() private view returns (uint256) {
        DGPInterface contractInterface = DGPInterface(_dgpAddress);
        return contractInterface.getGovernanceCollateral()[0];
    }

    // get list of governor addresses
    function getGovernorsAddresses() public view returns (address[] memory) {
        return governorAddresses;
    }

    // get total number of governors
    function governorCount() public view returns (uint16) {
        return _governorCount;
    }

    function ping() public {
        // check if a governor
        require(
            governors[tx.origin].blockHeight > 0,
            "Governance: Must be a governor to ping"
        );
        // check if governor is valid
        require(
            isValidGovernor(tx.origin, false, false),
            "Governance: Governor is not currently valid"
        );
        // update ping
        governors[tx.origin].lastPing = block.number;
    }

    // enroll an address to be a governor
    // new addresses must supply the exact collateral in one transaction
    // if the required collateral has increased allow addresses to top up
    function enroll() public payable {
        // must send an amount
        require(
            msg.value > 0,
            "Governance: Collateral is required for enrollment"
        );
        uint256 requiredCollateral = getRequiredCollateral();
        // check if new enrollment or topup
        if (governors[msg.sender].blockHeight > 0) {
            // address is already a governor. If the collateral has increase, allow a topup
            uint256 newCollateral = governors[msg.sender].collateral +
                msg.value;
            require(
                newCollateral == requiredCollateral,
                "Governance: Topup collateral must be exact"
            );
            governors[msg.sender].collateral = requiredCollateral;
            governors[msg.sender].lastPing = block.number;
            governors[msg.sender].lastReward = 0;
        } else {
            // haven't reached maximum governors
            require(
                _governorCount < _maximumGovernors,
                "Governance: The maximum number of governors has been reached"
            );
            // address is a not already a governor. collateral must be exact
            require(
                msg.value == requiredCollateral,
                "Governance: New collateral must be exact"
            );
            // add governor
            governors[msg.sender] = Governor({
                collateral: requiredCollateral,
                blockHeight: block.number,
                lastPing: block.number,
                lastReward: 0,
                addressIndex: _governorCount
            });
            _governorCount++;
            governorAddresses.push(msg.sender);
        }
    }

    // unenroll as a governor
    // this will refund the addresses collateral
    function unenroll(bool force) public {
        // check if a governor
        require(
            governors[msg.sender].blockHeight > 0,
            "Must be a governor to unenroll"
        );
        uint256 requiredCollateral = getRequiredCollateral();
        // check blocks have passed to make a change
        uint256 enrolledAt = governors[msg.sender].blockHeight +
            _blockBeforeMatureGovernor;
        require(block.number > enrolledAt, "Too early to unenroll");
        if (!force && governors[msg.sender].collateral > requiredCollateral) {
            // if the required collateral has changed allow it to be reduce without unenrolling
            uint256 refund = governors[msg.sender].collateral -
                requiredCollateral;
            // safety check balance
            require(
                payable(address(this)).balance >= refund,
                "Governance: Contract does not contain enough funds"
            );
            // update governor
            governors[msg.sender].collateral = requiredCollateral;
            governors[msg.sender].lastPing = block.number;
            // send refund
            (bool sent, ) = payable(msg.sender).call{value: refund}("");
            if (!sent) {
                (bool stash, ) = payable(_budgetAddress).call{value: refund}(
                    ""
                );
                if (!stash) {
                    (bool burn, ) = payable(address(0x0)).call{value: refund}(
                        ""
                    );
                    require(
                        burn,
                        "Governance: Failed to stash then failed to burn"
                    );
                }
            }
            // reset last reward
            governors[msg.sender].lastReward = 0;
        } else {
            removeGovernor(msg.sender);
        }
    }

    function removeGovernor(address governorAddress) private {
        uint256 refund = governors[governorAddress].collateral;
        uint16 addressIndex = governors[governorAddress].addressIndex;
        // safety check balance
        require(
            address(this).balance >= refund,
            "Governance: Contract does not contain enough funds"
        );
        // remove governor
        delete governors[governorAddress];
        _governorCount--;
        // replace item in array
        uint16 arrayLen = uint16(governorAddresses.length);
        if (addressIndex < arrayLen) {
            governorAddresses[addressIndex] = governorAddresses[arrayLen - 1];
            address updateAddr = governorAddresses[addressIndex];
            governors[updateAddr].addressIndex = addressIndex;
        }
        // remove last element from array
        delete governorAddresses[arrayLen - 1];
        // refund
        (bool sent, ) = payable(governorAddress).call{value: refund}("");
        if (!sent) {
            (bool stash, ) = payable(_budgetAddress).call{value: refund}("");
            if (!stash) {
                (bool burn, ) = payable(address(0x0)).call{value: refund}("");
                require(
                    burn,
                    "Governance: Failed to stash then failed to burn"
                );
            }
        }
    }

    // returns true if a governor exists, is mature and has the correct collateral
    function isValidGovernor(
        address governorAddress,
        bool checkPing,
        bool checkCanVote
    ) public view returns (bool valid) {
        // must be a mature governor
        if (
            block.number - governors[governorAddress].blockHeight <
            _blockBeforeMatureGovernor
        ) {
            return false;
        }
        // must have the right collateral
        uint256 requiredCollateral = getRequiredCollateral();
        if (governors[governorAddress].collateral != requiredCollateral) {
            return false;
        }
        // must have sent a recent ping
        if (
            checkPing &&
            block.number - governors[governorAddress].lastPing >
            _pingBlockInterval
        ) {
            return false;
        }
        // must wait 28 days to vote
        if (
            checkCanVote &&
            block.number - governors[governorAddress].blockHeight <
            _blockBeforeGovernorVote
        ) {
            return false;
        }
        return true;
    }

    // ------------------------------
    // -------- REWARD SYSTEM -------
    // ------------------------------

    function rewardGovernor(address winner) public payable {
        // amount must be the equal to the reward amount
        require(
            block.number > _lastRewardBlock,
            "Governance: A Reward has already been paid in this block"
        );
        _lastRewardBlock = block.number;
        if (winner != address(uint160(0x0))) {
            // check valid winner
            isValidWinner(winner);
            // pay governor
            governors[winner].lastReward = block.number;
            (bool sent, ) = payable(winner).call{value: msg.value}("");
            if (!sent) {
                (bool burned, ) = payable(address(0x0)).call{value: msg.value}(
                    ""
                );
                require(burned, "Governance: Failed to burn failed reward");
            }
        } else {
            (bool burned, ) = payable(address(0x0)).call{value: msg.value}("");
            require(burned, "Governance: Failed to burn failed reward");
        }
    }

    function isValidWinner(address winner) private view returns (bool) {
        require(
            isValidGovernor(winner, true, false),
            "Governance: Address is not a valid governor"
        );
        require(
            block.number - 1920 >= governors[winner].blockHeight,
            "Governance: Address Immature"
        );
        require(
            block.number - governors[winner].lastReward >= _rewardBlockInterval,
            "Governance: Last reward too recent"
        );
        return true;
    }

    function currentWinner() public view returns (address winner) {
        uint16 i;
        for (i = 0; i < _governorCount; i++) {
            if (
                isValidGovernor(governorAddresses[i], true, false) &&
                block.number - governors[governorAddresses[i]].lastReward >=
                _rewardBlockInterval
            ) {
                return governorAddresses[i];
            }
        }
        return address(uint160(0x0));
    }

    function removeInactiveGovernor() public {
        // check 2 governors at a time which will allow for all governors to be checked
        // once per day and limits the gas usage for each block
        uint16 i;
        for (i = _inactiveGovernorIndex; i < _inactiveGovernorIndex + 2; i++) {
            if (i >= _governorCount) {
                // no point continuing as we have reached the end of the list
                break;
            }
            if (
                block.number - governors[governorAddresses[i]].lastPing >
                _pingBlockInterval
            ) {
                removeGovernor(governorAddresses[i]);
                break;
            }
        }
        _inactiveGovernorIndex += 2;
        if (_inactiveGovernorIndex >= _governorCount) {
            _inactiveGovernorIndex = 0;
        }
    }
}
