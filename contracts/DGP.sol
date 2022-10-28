// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./Governance.sol";

// interfaces
interface GasScheduleInterface {
    function getSchedule() external view returns (uint32[39] memory);
}

interface BlockSizeInterface {
    function getBlockSize() external view returns (uint32[1] memory);
}

interface MinGasPriceInterface {
    function getMinGasPrice() external view returns (uint32[1] memory);
}

interface BlockGasLimitInterface {
    function getBlockGasLimit() external view returns (uint64[1] memory);
}

interface TransactionFeeRatesInterface {
    function getTransactionFeeRates() external view returns (uint64[3] memory);
}

interface GovernanceCollateralInterface {
    function getGovernanceCollateral()
        external
        view
        returns (uint256[1] memory);
}

interface BudgetFeeInterface {
    function getBudgetFee() external view returns (uint256[1] memory);
}


contract DGP {
    // events
    event NewProposal(ProposalType proposalType, address proposalAddress); // Emitted when a new proposal is made
    event ProposalPassed(ProposalType proposalType, address proposalAddress); // Emitted when a new proposal is passed

    // proposals
    enum ProposalType {
        NONE,
        GASSCHEDULE,
        BLOCKSIZE,
        MINGASPRICE,
        BLOCKGASLIMIT,
        TRANSACTIONFEERATES,
        COLLATERAL,
        BUDGETFEE
    }
    struct Proposal {
        bool onVote;
        address[] votes;
        address proposalAddress;
        uint256 proposalHeight;
        ProposalType proposalType;
    }
    uint16 private _proposalExpiryBlocks = 14 * 960; // blocks for proposal to expire
    Proposal public proposal; // current proposal
    uint16 private _minimumGovernors = 100; // how many governors must exist before voting is enabled
    address payable immutable public governanceAddress; // address of governance contract

    // DGP
    address public gasScheduleAddress =
        address(0x0000000000000000000000000000000000000080);
    address public blockSizeAddress =
        address(0x0000000000000000000000000000000000000081);
    address public minGasPriceAddress =
        address(0x0000000000000000000000000000000000000082);
    address public blockGasLimitAddress =
        address(0x0000000000000000000000000000000000000083);
    address public transactionFeeRatesAddress =
        address(0x0000000000000000000000000000000000000084);
    address public governanceCollateralAddress =
        address(0x0000000000000000000000000000000000000086);
    address public budgetFeeAddress =
        address(0x0000000000000000000000000000000000000087);

    uint256 public immutable defaultGovernanceCollateral = 75E13;
    uint256 public immutable defaultBudgetFee = 6E13;
    uint64 public immutable  defaultMinRelayTxFee = 1E9;
    uint64 public immutable  defaultIncrementalRelayFee = 1E9;
    uint64 public immutable defaultDustRelayFee = 3E9;
    uint32 public immutable defaultMinGasPrice = 5000;
    uint64 public immutable defaultBlockGasLimit = 4E7;
    uint32 public immutable defaultBlockSize = 2E6;
    uint32[39] public defaultGasSchedule = [
        10, //0: tierStepGas0
        10, //1: tierStepGas1
        10, //2: tierStepGas2
        10, //3: tierStepGas3
        10, //4: tierStepGas4
        10, //5: tierStepGas5
        10, //6: tierStepGas6
        10, //7: tierStepGas7
        10, //8: expGas
        50, //9: expByteGas
        30, //10: sha3Gas
        6, //11: sha3WordGas
        200, //12: sloadGas
        20000, //13: sstoreSetGas
        5000, //14: sstoreResetGas
        15000, //15: sstoreRefundGas
        1, //16: jumpdestGas
        375, //17: logGas
        8, //18: logDataGas
        375, //19: logTopicGas
        32000, //20: createGas
        700, //21: callGas
        2300, //22: callStipend
        9000, //23: callValueTransferGas
        25000, //24: callNewAccountGas
        24000, //25: suicideRefundGas
        3, //26: memoryGas
        512, //27: quadCoeffDiv
        200, //28: createDataGas
        21000, //29: txGas
        53000, //30: txCreateGas
        4, //31: txDataZeroGas
        68, //32: txDataNonZeroGas
        3, //33: copyGas
        700, //34: extcodesizeGas
        700, //35: extcodecopyGas
        400, //36: balanceGas
        5000, //37: suicideGas
        24576 //38: maxCodeSize
    ];


    uint256 public immutable maxGovernanceCollateral = 75E14;
    uint256 public immutable maxBudgetFee = 6E15;
    uint64 public immutable maxMinRelayTxFee = 1E11;
    uint64 public immutable maxIncrementalRelayFee = 1E11;
    uint64 public immutable maxDustRelayFee = 3E11;
    uint64 public immutable maxMinGasPrice = 1E4;
    uint64 public immutable minBlockGasLimit= 1E6;
    uint64 public immutable maxBlockGasLimit= 1E9;
    uint32 public immutable minBlockSize= 5E5;
    uint32 public immutable maxBlockSize= 32E6;

    


    constructor(){
        governanceAddress = payable(address(new Governance(payable(address(this)))));
    }

    // ------------------------------
    // ------- PROPOSAL VOTING ------
    // ------------------------------

    // add new proposal or vote on existing proposal  
    function addProposal(ProposalType proposalType, address proposalAddress)
        public
    {
        Governance contractInterface = Governance(
            governanceAddress
        );
        uint16 governorCount = contractInterface.governorCount();

        // must be minimum governors
        require(
            governorCount >= _minimumGovernors,
            "DGP: Not enough governors to enable voting"
        );
        // address must be governor
        require(
            contractInterface.isValidGovernor(msg.sender, true, true),
            "DGP: Only valid governors can create proposals"
        );
        // update ping time
        contractInterface.ping(msg.sender);
        // check a vote isn't active
        if (!proposal.onVote) {
            require(
                validateProposedContract(proposalType, proposalAddress) == true,
                "DGP: The proposed contract did not operate as expected"
            );
            proposal.onVote = true; // put proposal on vote, no changes until vote is setteled or removed
            proposal.proposalAddress = proposalAddress; // set new proposal for vote
            proposal.proposalType = proposalType; // set type of proposal vote
            proposal.proposalHeight = block.number; // set new proposal initial height
            delete proposal.votes; // clear votes
            proposal.votes.push(msg.sender); // add sender vote
            emit NewProposal(proposalType, proposalAddress); // alert listeners
        } else if (
            block.number - proposal.proposalHeight > _proposalExpiryBlocks
        ) {
            // check if vote has expired
            clearCollateralProposal();
        } else if (
            proposal.proposalAddress == proposalAddress &&
            proposal.proposalType == proposalType &&
            !alreadyVoted()
        ) {
            proposal.votes.push(msg.sender); // add sender vote
        }

        // check if vote has passed a simple majority (51%)
        if (
            proposal.onVote && proposal.votes.length >= (governorCount / 2 + 1)
        ) {
            proposalPassed();
            // alert listeners
            emit ProposalPassed(
                proposal.proposalType,
                proposal.proposalAddress
            );
            // clear proposal
            clearCollateralProposal();
        }
    }

    function proposalPassed() private {
        if (proposal.proposalType == ProposalType.GASSCHEDULE) {
            // update gas schedule contract address
            gasScheduleAddress = proposal.proposalAddress;
        } else if (proposal.proposalType == ProposalType.BLOCKSIZE) {
            // update block size contract address
            blockSizeAddress = proposal.proposalAddress;
        } else if (proposal.proposalType == ProposalType.MINGASPRICE) {
            // update min gas price contract address
            minGasPriceAddress = proposal.proposalAddress;
        } else if (proposal.proposalType == ProposalType.BLOCKGASLIMIT) {
            // update block gas limit contract address
            blockGasLimitAddress = proposal.proposalAddress;
        } else if (proposal.proposalType == ProposalType.TRANSACTIONFEERATES) {
            // update fee rates contract address
            transactionFeeRatesAddress = proposal.proposalAddress;
        } else if (proposal.proposalType == ProposalType.COLLATERAL) {
            // update collateral
            governanceCollateralAddress = proposal.proposalAddress;
        } else if (proposal.proposalType == ProposalType.BUDGETFEE) {
            // update budget listing fee
            budgetFeeAddress = proposal.proposalAddress;
        }
    }

    function clearCollateralProposal() private {
        proposal.proposalAddress = address(uint160(0x0)); // clear amount
        proposal.proposalType = ProposalType.NONE; // clear type
        delete proposal.votes; // clear votes
        proposal.proposalHeight = 0; // clear proposal height
        proposal.onVote = false; // open submission
    }

    function alreadyVoted() private view returns (bool voted) {
        for (uint16 i = 0; i < proposal.votes.length; i++) {
            if (proposal.votes[i] == msg.sender) return true;
        }
        return false;
    }

    // validate the proposed contract address returns the data as expected
    function validateProposedContract(
        ProposalType proposalType,
        address proposalAddress
    ) private view returns (bool valid) {
        if (proposalType == ProposalType.GASSCHEDULE) {
            GasScheduleInterface contractInterface = GasScheduleInterface(
                proposalAddress
            );
            uint32[39] memory result = contractInterface.getSchedule();
            for (uint8 i = 0; i < 39; i++) {
                if (result[i] == 0) return false;
            }
            return true;
        } else if (proposalType == ProposalType.BLOCKSIZE) {
            BlockSizeInterface ci = BlockSizeInterface(proposalAddress);
            uint32[1] memory size = ci.getBlockSize();
            if (size[0] > minBlockSize && size[0] <= maxBlockSize) return true;
        } else if (proposalType == ProposalType.MINGASPRICE) {
            MinGasPriceInterface ci = MinGasPriceInterface(proposalAddress);
            uint32[1] memory price = ci.getMinGasPrice();
            if (price[0] > 0 && price[0] <= maxMinGasPrice) return true;
        } else if (proposalType == ProposalType.BLOCKGASLIMIT) {
            BlockGasLimitInterface ci = BlockGasLimitInterface(proposalAddress);
            uint64[1] memory limit = ci.getBlockGasLimit();
            if (limit[0] > minBlockGasLimit && limit[0] <= maxBlockGasLimit) return true;
        } else if (proposalType == ProposalType.TRANSACTIONFEERATES) {
            TransactionFeeRatesInterface ci = TransactionFeeRatesInterface(
                proposalAddress
            );
            uint64[3] memory result = ci.getTransactionFeeRates();
            if(result[0] == 0 || result[0] > maxMinRelayTxFee) {
                return false;
            }
            if(result[1] == 0 || result[1] > maxIncrementalRelayFee) {
                return false;
            }
            if(result[2] == 0 || result[2] > maxDustRelayFee) {
                return false;
            }
            return true;
        } else if (proposalType == ProposalType.COLLATERAL) {
            GovernanceCollateralInterface ci = GovernanceCollateralInterface(
                proposalAddress
            );
            uint256[1] memory collateral = ci.getGovernanceCollateral();
            if (collateral[0] > 0 && collateral[0] <= maxGovernanceCollateral) return true;
        } else if (proposalType == ProposalType.BUDGETFEE) {
            BudgetFeeInterface ci = BudgetFeeInterface(proposalAddress);
            uint256[1] memory fee = ci.getBudgetFee();
            if (fee[0] > 0 && fee[0] <= maxBudgetFee) return true;
        }
        return false;
    }

    // ------------------------------
    // ------------ DGP -------------
    // ------------------------------
    function getSchedule() public view returns (uint32[39] memory) {
        GasScheduleInterface contractInterface = GasScheduleInterface(
            gasScheduleAddress
        );
        uint32[39] memory schedule =  contractInterface.getSchedule();
        for(uint i = 0; i < 39; i++){
            if(schedule[i] == 0 || schedule[i] < defaultGasSchedule[i] / 100 || schedule[i] > defaultGasSchedule[i] * 1000){
                schedule[i] = defaultGasSchedule[i];
            }
        }
        return schedule;
    }

    function getBlockSize() public view returns (uint32[1] memory) {
        BlockSizeInterface contractInterface = BlockSizeInterface(
            blockSizeAddress
        );
        uint32[1] memory size =  contractInterface.getBlockSize();
         if(size[0] < minBlockSize || size[0] > maxBlockSize) return [defaultBlockSize];
        return size;
    }

    function getMinGasPrice() public view returns (uint32[1] memory) {
        MinGasPriceInterface contractInterface = MinGasPriceInterface(
            minGasPriceAddress
        );
        uint32[1] memory price =  contractInterface.getMinGasPrice();
        if(price[0] < 1 || price[0] > maxMinGasPrice) return [defaultMinGasPrice];
        return price;
    }

    function getBlockGasLimit() public view returns (uint64[1] memory) {
        BlockGasLimitInterface contractInterface = BlockGasLimitInterface(
            blockGasLimitAddress
        );
        uint64[1] memory limit =  contractInterface.getBlockGasLimit();
        if(limit[0] < minBlockGasLimit || limit[0] > maxBlockGasLimit) return [defaultBlockGasLimit];
        return limit;
    }

    function getTransactionFeeRates() public view returns (uint64[3] memory) {
        TransactionFeeRatesInterface contractInterface = TransactionFeeRatesInterface(
                transactionFeeRatesAddress
            );
         uint64[3] memory rates =  contractInterface.getTransactionFeeRates();
         if(rates[0] <= 0 || rates[0] > maxMinRelayTxFee) rates[0] = defaultMinRelayTxFee;
         if(rates[1] <= 0 || rates[1] > maxIncrementalRelayFee) rates[1] = defaultIncrementalRelayFee;
         if(rates[2] <= 0 || rates[2] > maxDustRelayFee) rates[2] = defaultDustRelayFee;
        return  rates;
    }

    function getGovernanceCollateral() public view returns (uint256[1] memory) {
        GovernanceCollateralInterface contractInterface = GovernanceCollateralInterface(
                governanceCollateralAddress
            );
        uint256[1] memory collateral =  contractInterface.getGovernanceCollateral();
        return collateral[0] > 0 && collateral[0] <= maxGovernanceCollateral ? collateral : [defaultGovernanceCollateral];
    }

    function getBudgetFee() public view returns (uint256[1] memory) {
        BudgetFeeInterface contractInterface = BudgetFeeInterface(
            budgetFeeAddress
        );
        uint256[1] memory fee =  contractInterface.getBudgetFee();
        return fee[0] > 0 && fee[0] <= maxBudgetFee ? fee : [defaultBudgetFee];
    }
}
