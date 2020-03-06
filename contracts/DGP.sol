pragma solidity 0.5.8;
import "./SafeMath.sol";

// interfaces
contract GasScheduleInterface {
    function getSchedule() public view returns (uint32[39] memory);
}
contract BlockSizeInterface {
    function getBlockSize() public view returns (uint32[1] memory);
}
contract MinGasPriceInterface {
    function getMinGasPrice() public view returns (uint32[1] memory);
}
contract BlockGasLimitInterface {
    function getBlockGasLimit() public view returns (uint32[1] memory);
}
contract GovernanceCollateralInterface {
    function getGovernanceCollateral() public view returns (uint256[1] memory);
}
contract BudgetFeeInterface {
    function getBudgetFee() public view returns (uint256[1] memory);
}
contract GovernanceInterface {
    function isValidGovernor(address governorAddress, bool checkPing)
        public
        view
        returns (bool valid);
    function ping() public;
    function governorCount() public returns (uint16);
}

contract DGP {
    // imports
    using SafeMath for uint256;

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
    uint16 private _proposalExpiryBlocks = 5; // blocks for proposal to expire
    Proposal public proposal; // current proposal
    uint16 private _minimumGovernors = 100; // how many governors must exist before voting is enabled
    address private _governanceAddress = address(
        0x0000000000000000000000000000000000000087
    ); // address of governance contract

    // DGP
    address public gasScheduleAddress = address(
        0x0000000000000000000000000000000000000080
    );
    address public blockSizeAddress = address(
        0x0000000000000000000000000000000000000081
    );
    address public minGasPriceAddress = address(
        0x0000000000000000000000000000000000000082
    );
    address public blockGasLimitAddress = address(
        0x0000000000000000000000000000000000000083
    );
    address public governanceCollateralAddress = address(
        0x0000000000000000000000000000000000000084
    );
    address public budgetFeeAddress = address(
        0x0000000000000000000000000000000000000085
    );

    // ------------------------------
    // ------- PROPOSAL VOTING ------
    // ------------------------------

    // add new proposal or vote on existing proposal to change the governor collateral
    function addProposal(ProposalType proposalType, address proposalAddress)
        public
    {
        GovernanceInterface contractInterface = GovernanceInterface(
            _governanceAddress
        );
        uint16 governorCount = contractInterface.governorCount();

        // must be minimum governors
        require(
            governorCount >= _minimumGovernors,
            "Not enough governors to enable voting"
        );
        // address must be governor
        require(
            contractInterface.isValidGovernor(msg.sender, true),
            "Only valid governors can create proposals"
        );
        // update ping time
        contractInterface.ping();
        // check a vote isn't active
        if (!proposal.onVote) {
            require(
                validateProposedContract(proposalType, proposalAddress) == true,
                "The proposed contract did not operate as expected"
            );
            proposal.onVote = true; // put proposal on vote, no changes until vote is setteled or removed
            proposal.proposalAddress = proposalAddress; // set new proposal for vote
            proposal.proposalType = proposalType; // set type of proposal vote
            proposal.proposalHeight = block.number; // set new proposal initial height
            delete proposal.votes; // clear votes
            proposal.votes.push(msg.sender); // add sender vote
            emit NewProposal(proposalType, proposalAddress); // alert listeners
        } else if (
            block.number.sub(proposal.proposalHeight) > _proposalExpiryBlocks
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
        uint16 i;
        for (i = 0; i < proposal.votes.length; i++) {
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
            uint8 i;
            for (i = 0; i < 39; i++) {
                if (result[i] == 0) return false;
            }
            return true;
        } else if (proposalType == ProposalType.BLOCKSIZE) {
            BlockSizeInterface ci = BlockSizeInterface(proposalAddress);
            if (ci.getBlockSize()[0] > 0) return true;
        } else if (proposalType == ProposalType.MINGASPRICE) {
            MinGasPriceInterface ci = MinGasPriceInterface(proposalAddress);
            if (ci.getMinGasPrice()[0] > 0) return true;
        } else if (proposalType == ProposalType.BLOCKGASLIMIT) {
            BlockGasLimitInterface ci = BlockGasLimitInterface(proposalAddress);
            if (ci.getBlockGasLimit()[0] > 0) return true;
        } else if (proposalType == ProposalType.COLLATERAL) {
            GovernanceCollateralInterface ci = GovernanceCollateralInterface(
                proposalAddress
            );
            if (ci.getGovernanceCollateral()[0] > 0) return true;
        } else if (proposalType == ProposalType.BUDGETFEE) {
            BudgetFeeInterface ci = BudgetFeeInterface(proposalAddress);
            if (ci.getBudgetFee()[0] > 0) return true;
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
        return contractInterface.getSchedule();
    }
    function getBlockSize() public view returns (uint32[1] memory) {
        BlockSizeInterface contractInterface = BlockSizeInterface(
            blockSizeAddress
        );
        return contractInterface.getBlockSize();
    }
    function getMinGasPrice() public view returns (uint32[1] memory) {
        MinGasPriceInterface contractInterface = MinGasPriceInterface(
            minGasPriceAddress
        );
        return contractInterface.getMinGasPrice();
    }
    function getBlockGasLimit() public view returns (uint32[1] memory) {
        BlockGasLimitInterface contractInterface = BlockGasLimitInterface(
            blockGasLimitAddress
        );
        return contractInterface.getBlockGasLimit();
    }
    function getGovernanceCollateral() public view returns (uint256[1] memory) {
        GovernanceCollateralInterface contractInterface = GovernanceCollateralInterface(
            governanceCollateralAddress
        );
        return contractInterface.getGovernanceCollateral();
    }
    function getBudgetFee() public view returns (uint256[1] memory) {
        BudgetFeeInterface contractInterface = BudgetFeeInterface(
            budgetFeeAddress
        );
        return contractInterface.getBudgetFee();
    }

    // Dev function for contract testing to allow the governance
    // address to be manually set due to the circular dependency
    function dev_setGovernanceAddress(address contractAddress) public {
        require(
            _governanceAddress == address(uint160(0x0)),
            "_governanceAddress already set"
        );
        _governanceAddress = contractAddress;
    }
}
