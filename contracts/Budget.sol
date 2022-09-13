// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./DGP.sol";
import "./Governance.sol";


contract Budget {
    // address of the external contracts
    address payable immutable public dgpAddress;
    address payable immutable  public governanceAddress;

    // Data structures
    enum Vote {
        NEW,
        ABSTAIN,
        NO,
        YES
    }
    struct BudgetProposal {
        uint8 id;
        address owner;
        string title;
        string desc;
        string url;
        uint256 requested;
        uint8 duration;
        uint8 durationsPaid;
        uint16 yesVote;
        uint16 noVote;
        bool remove;
    }
    mapping(uint8 => mapping(address => uint16)) votes;
    BudgetProposal[] public proposals; // List of existing proposals
    uint8 private _currentProposalId = 0; // used so each proposal can be identified for voting
    uint8 private _proposalCount = 0; // number of active proposals
    uint8 private _maximumActiveProposals = 8; // maximum number of active proposals at any time
    uint16 private _minimumGovernors = 100; // how many governors must exist before budget can be settled

    // Event that will be emitted whenever a new proposal is started
    event ProposalStarted(
        uint8 id,
        address owner,
        string title,
        string desc,
        string url,
        uint256 requested,
        uint8 duration
    );

    // budget block details
    uint256 private _budgetPeriod = 29220; // 365.25/12*960
    uint256 _budgetNextSettlementBlock = _budgetPeriod;


    constructor(address payable _dgpAddress, address payable _governanceAddress){
        dgpAddress = _dgpAddress;
        governanceAddress = _governanceAddress;
    }

    /** @dev Function to start a new proposal.
     * @param title Title of the proposal to be created
     * @param description Brief description about the proposal
     * @param url Url for the project
     * @param requested Amount being requested in satoshis
     * @param duration Duration of the payments in months
     */
    function startProposal(
        string memory title,
        string memory description,
        string memory url,
        uint256 requested,
        uint8 duration
    ) public payable {
        DGP contractInterface = DGP(dgpAddress);
        uint256 listingFee = contractInterface.getBudgetFee()[0];
        // limit number of active proposals
        require(
            _proposalCount < _maximumActiveProposals,
            "Maximum active proposals reached"
        );
        // must pay listing fee
        require(msg.value == listingFee, "Buget listing fee is required");
        // must have duration and requested amount
        require(requested > 0, "Requested amount cannot be less than 1");
        require(duration > 0, "Requested duration cannot be less than 1");
        require(duration < 13, "Requested duration cannot be greater than 12");
        // create new proposal
        _currentProposalId++;
        _proposalCount++;
        BudgetProposal memory newProp;
        newProp.id = _currentProposalId;
        newProp.owner = msg.sender;
        newProp.title = title;
        newProp.desc = description;
        newProp.url = url;
        newProp.requested = requested;
        newProp.duration = duration;
        newProp.durationsPaid = 0;
        newProp.yesVote = 0;
        newProp.noVote = 0;
        newProp.remove = false;
        // add proposal to array
        bool pushProposal = true;
        for (uint8 i = 0; i < proposals.length; i++) {
            if (proposals[i].remove) {
                proposals[i] = newProp;
                pushProposal = false;
                break;
            }
        }
        if (pushProposal) proposals.push(newProp);
        // emit event
        emit ProposalStarted(
            _currentProposalId,
            msg.sender,
            title,
            description,
            url,
            requested,
            duration
        );
    }

    /** @dev Function to vote on a proposal.
     * @param proposalId Id of the proposal being voted on
     * @param vote the vote being cast (no, yes, abstain)
     */
    function voteForProposal(uint8 proposalId, Vote vote) public {
        Governance governanceInterface = Governance(
            governanceAddress
        );
        // must be a valid governor
        require(
            governanceInterface.isValidGovernor(msg.sender, true, true),
            "Address is not a valid governor"
        );
        // must be a valid proposal
        int16 proposalRawIndex = getProposalIndex(proposalId);
        require(proposalRawIndex >= 0, "Proposal not found");
        uint8 proposalIndex = uint8(uint16(proposalRawIndex));
        // create unique vote value to handle reusing memory of old budgets
        uint16 voteData = uint16(proposalId) << 8;
        voteData |= uint16(vote);
        // if vote was changed remove previous

        bool isNewVote = votes[proposalIndex][msg.sender] != voteData;
        // get governor current vote
        Vote currentVote = getVote(
            votes[proposalIndex][msg.sender],
            proposalId
        );
        // update vote on proposal
        if (isNewVote) {
            if (currentVote == Vote.YES) proposals[proposalIndex].yesVote--;
            if (currentVote == Vote.NO) proposals[proposalIndex].noVote--;
            if (vote == Vote.YES) proposals[proposalIndex].yesVote++;
            if (vote == Vote.NO) proposals[proposalIndex].noVote++;
        }
        // log vote
        votes[proposalIndex][msg.sender] = voteData;
        // update governor ping
        governanceInterface.ping();
    }

    /** @dev Function to get a a governors current vote for the proposals.
     * @param voteData vote data for the governor
     * @param proposalId Id of the proposal
     */
    function getVote(uint16 voteData, uint8 proposalId)
        private
        pure
        returns (Vote)
    {
        uint8 extractedPropId = uint8(voteData >> 8);
        if (extractedPropId == proposalId) {
            uint8 extractedVote = uint8(voteData);
            return Vote(extractedVote);
        }
        return Vote.NEW;
    }

    /** @dev Function to get a proposal by it's id.
     * @param proposalId Id of the proposal
     */
    function getProposalIndex(uint8 proposalId) public view returns (int16) {
        for (uint8 i = 0; i < proposals.length; i++) {
            if (proposals[i].id == proposalId && !proposals[i].remove)
                return int16(uint16(i));
        }
        return -1;
    }

    /** @dev Function to fund contract.
     * These funds are paid in each new block and can also be donated to.
     * Any unused funds will be destroyed
     */
    function fund() public payable {}

    /** @dev Function to return current contract funds.
     */
    function balance() public view returns (uint256) {
        return payable(address(this)).balance;
    }

    /** @dev Function to fund the budget in the coinstake as well as
     * settle the budget in the appropraite block.
     */
    function settleBudget() public payable {
        // must be done on correct block
        if (block.number < _budgetNextSettlementBlock) return;
        // set new budget block
        _budgetNextSettlementBlock = block.number + _budgetPeriod;
        // create governance contract interface
        Governance governanceInterface = Governance(
            governanceAddress
        );
        uint16 governorCount = governanceInterface.governorCount();
        bool canSettleBudget = governorCount >= _minimumGovernors;
        uint16 requiredVote = governorCount / 10;

        if (canSettleBudget) {
            // iterate through all projects
            // failed projects are removed
            // complete projects are removed
            // active projects that are passing are funded
            // active projects that have completed funded are moved to complete for 1 budget cycle
            uint8 i;
            for (i = 0; i < proposals.length; i++) {
                // skip removed proposals
                if (proposals[i].remove) continue;
                // remove failed proposals
                if (!hasVotePassed(proposals[i], requiredVote)) {
                    removeProposal(i);
                } else {
                    // allocate any funds for active projects
                    if (proposals[i].durationsPaid < proposals[i].duration) {
                        if (payable(address(this)).balance >= proposals[i].requested) {
                            // fund project
                            proposals[i].durationsPaid += 1;
                            (bool sent, ) = payable(proposals[i].owner).call{
                                value: proposals[i].requested
                            }("");
                        }
                    }
                    // remove project if complete
                    if (proposals[i].durationsPaid >= proposals[i].duration) {
                        removeProposal(i);
                    }
                }
            }
        }

        // destroy any left over funds
        if (payable(address(this)).balance > 0) {
            payable(address(0x0)).transfer(
                payable(address(this)).balance);
        }
    }

    function removeProposal(uint8 index) private {
        proposals[index].remove = true;
        _proposalCount--;
    }

    function hasVotePassed(BudgetProposal memory proposal, uint16 requiredVote)
        private
        pure
        returns (bool)
    {
        // passing vote requires more than 10% yes
        if (proposal.yesVote > proposal.noVote) {
            return (proposal.yesVote - proposal.noVote) > requiredVote;
        }
        return false;
    }

    /** @dev Function to return number of active proposals.
     */
    function proposalCount() public view returns (uint8) {
        return _proposalCount;
    }

    /** @dev Function to return number of active proposals.
     * @param proposalId Id of the proposal being voted on
     */
    function proposalVoteStatus(uint8 proposalId) public view returns (Vote) {
        int16 proposalRawIndex = getProposalIndex(proposalId);
        require(proposalRawIndex >= 0, "Proposal not found");
        uint8 proposalIndex = uint8(uint16(proposalRawIndex));
        return getVote(votes[proposalIndex][msg.sender], proposalId);
    }
}
