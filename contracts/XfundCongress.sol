pragma solidity ^0.4.16;

contract owned {
    address public owner;

    function owned()  public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) onlyOwner  public {
        owner = newOwner;
    }
}

contract tokenRecipient {
    event receivedEther(address sender, uint amount);
    event receivedTokens(address _from, uint256 _value, address _token, bytes _extraData);

    function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public {
        TransferableToken t = TransferableToken(_token); 
        require(t.transferFrom(_from, this, _value));
        receivedTokens(_from, _value, _token, _extraData);
    }

    function () payable  public {
        receivedEther(msg.sender, msg.value);
    }
}

interface TransferableToken {
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);
}
interface XfundToken {
    function balanceOf(address _address) public returns (uint256 balance);
    function votesReceived(address _nominee) public returns (uint256 votes);
    function voteList(address _voter) public returns (uint256 votedFor);
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success); //can now remove, but check first if you do
}

contract XfundCongress is owned, tokenRecipient {
    uint256 constant december25UTC = 1514188800;
    uint256 constant january1UTC = 1514793600;
    address supersedingCongress;
    bool congressActive = true;
    // Congress Parameters
    uint public minimumQuorum;
    uint public minDebatingPeriodInMinutes;
    uint public percentOfVotesForPassage;
    mapping (address => uint256) deposits;

    Proposal[] public proposals;
    uint public numProposals;

    // members of Congress are called members
    mapping (address => uint) public memberId;
    Member[] public members;
    address vetoPower; // The senior member of congress (by vote) can veto proposals with 33% of congress

    // Link to the voting token
    XfundToken public xfundToken;

    event ProposalAdded(uint proposalID, address transactionRecipient, uint amount, uint debatingPeriodInMinutes, string description);
    event Voted(uint proposalID, bool position, address voter, string justification);
    event ProposalTallied(uint proposalID, uint aprovalPercent, uint quorum, bool active);
    event MembershipChanged(address member, bool isMember);
    event ChangeOfRules(uint newMinimumQuorum, uint newMinDebatingPeriodInMinutes, uint newPercentOfVotesForPassage);
    event NewCongressSize(uint size, address caller);
    event NewVetoPower(address member);

    struct Proposal {
        address transactionRecipient;
        uint amount;
        string description;
        uint votingDeadline;
        uint elevatedPassagePercent; // some proposals should have elevated requirements for passage
        bool executed;
        bool proposalPassed;
        bool proposalRejected;
        uint numberOfVotes;
        uint yeas;
        uint nays;
        bool vetoed;
        bytes32 proposalHash;
        Vote[] votes;
        mapping (address => bool) voted;
    }

    struct Member {
        address memberAddress;
        string description;
        string identityLink;
        uint memberSince;
    }

    struct Vote {
        bool inSupport;
        address voter;
        string justification;
    }

    // Modifier that allows only congress to call function
    modifier onlyMembers {
        require(members[memberId[msg.sender]].memberAddress == msg.sender);
        _;
    }

    /**
     * Constructor function
     */
    function XfundCongress (
        uint minimumQuorumForProposals,
        uint minutesForDebate,
        uint _percentOfVotesForPassage,
        address tokenAddress
    )  payable public {
        changeVotingRules(minimumQuorumForProposals, minutesForDebate, _percentOfVotesForPassage);
        vetoPower = msg.sender;
        xfundToken = XfundToken(tokenAddress);
        members.length = 1;
        members[0] = Member({memberAddress: msg.sender, memberSince: now, description: "Founding Member", identityLink: ""});
    }

    /**
     * Make a deposit to the Xfund
     *
     */
    function deposit() payable public {
        deposits[msg.sender] += msg.value;
    }

    /**
     * Get back your deposit between dec25 and jan1 if total funds raised < 5 ether
     *
     */
    function projectFailedWithdraw() public {
        require(now > december25UTC && now < january1UTC);
        require(this.balance < 5 ether);
        uint256 donorDeposit = deposits[msg.sender];
        deposits[msg.sender] = 0;
        msg.sender.transfer(donorDeposit);
    }

    /**
     * To upgrade this contract with a replacement
     *
     * @param _newCongress The address of the upgraded contract
     * @param _newOwner who becomes the owner of this contract since it can no longer call onlyOwner functions itself
     */
    function upgrade(address _newCongress, address _newOwner) onlyOwner public {
        congressActive = false;
        supersedingCongress = _newCongress;
        owner = _newOwner;
    }
    /**
     * When further upgrades occur, keep `supersedingCongress` up to date
     *
     * @param _newCongress The address of the most current contract
     */
    function updateCurrentCongress(address _newCongress) onlyOwner public {
        supersedingCongress = _newCongress;
    }

    /**
     * Change the size of congress and update `minimumQuorum`
     *
     * @param _newSize New size of congress
     * @param _minimumQuorum New quorum to pass proposals
     */
    function changeCongressSize(uint16 _newSize, uint256 _minimumQuorum) onlyOwner public returns (uint256 size) {
        members.length = _newSize;
        minimumQuorum = _minimumQuorum;
        NewCongressSize(members.length, msg.sender);
        return members.length;
    }

    /**
     * Join congress if you have more votes than the minimum congressperson
     *
     * @param _identityDescription Description of yourself, most likely your name
     * @param _identityLink Link to any online profile, such as an ethereum identity project or social media profile
     */
    function joinCongress(string _identityDescription, string _identityLink) public returns (bool success) {
        // the 0x0 address is blocked from votes by xfundToken.voteOnCongress(...). This is important.
        require(xfundToken.balanceOf(msg.sender) > 0);                       // Has tokens
        require(members[memberId[msg.sender]].memberAddress != msg.sender); // not already a member
        //require(xfundToken.voteList(msg.sender) == 0x0);                     // Has not nominated anyone.  (removed)

        uint256 votesOfApplicant = xfundToken.votesReceived(msg.sender);

        uint256 minCongresspersonVotes = xfundToken.votesReceived(members[0].memberAddress); // initialize minCongresspersonVotes
        uint16 juniorMember = 0;
        for (uint16 i=1; i<members.length; i++) { // find minCongresspersonVotes
            // WARNING: if someone has so many votes as to overflow a uint256, they should transfer tokens, or update the contract. Inside loop, saving gas.
            // Overflow check of the suspected junior member is deferred until after the loop.
            uint256 memberVotes = xfundToken.votesReceived(members[i].memberAddress);
            if (memberVotes <= minCongresspersonVotes) { // in case of tied vote, give new member higher index.  This does increase gas cost when minConVotes=0 and many congress vacancies.
                minCongresspersonVotes = memberVotes;
                juniorMember = i;
            }
        }
        // now check for overflow of the selected junior member
        require(xfundToken.balanceOf(members[juniorMember].memberAddress) + xfundToken.votesReceived(members[juniorMember].memberAddress) >= xfundToken.balanceOf(members[juniorMember].memberAddress));
        if (votesOfApplicant > minCongresspersonVotes) {
            MembershipChanged(members[juniorMember].memberAddress, false);
            memberId[members[juniorMember].memberAddress] = 0;
            memberId[msg.sender] = juniorMember;
            members[juniorMember] = Member({memberAddress: msg.sender, memberSince: now, description: _identityDescription, identityLink: _identityLink});
            success = true;
            MembershipChanged(msg.sender, true);
        } else {
            success = false;
            //MembershipChanged(msg.sender, false);
        }
    }

    /// @notice Get current size of congress
    function getCongressSize() constant public returns (uint256) {
        return members.length;
    }

    /**
     * Update which congressperson has the veto power by finding the member with maximum votes
     *
     */
    function updateVetoPower() onlyOwner public returns (address updatedVetoPower) {
        // if no members have any votes, this sets the vetoPower to 0x0
        // updatedVetoPower already set to 0x0
        uint256 maxCongresspersonVotes = 0;
        bool foundVetoPower;
        for (uint16 i=0; i<members.length; i++) {
            uint256 memberVotes = xfundToken.balanceOf(members[i].memberAddress) + xfundToken.votesReceived(members[i].memberAddress); // WARN: no overflow check
            if (memberVotes > maxCongresspersonVotes) { // in case of tie (seems unlikely, and even less likely to persist) grant power to member with lower index
                maxCongresspersonVotes = memberVotes;
                uint16 newVetoIndex = i;
                foundVetoPower = true;
            }
        }
        if (vetoPower != members[newVetoIndex].memberAddress && foundVetoPower) {
            vetoPower = members[newVetoIndex].memberAddress;
            NewVetoPower(vetoPower);
        }
        return vetoPower;
    }

    /**
     * Change voting rules
     *
     * Make so that proposals need tobe discussed for at least `minutesForDebate/60` hours,
     * have at least `minimumQuorumForProposals` votes, and have 50% + `newPercentOfVotesForPassage` votes to be executed
     *
     * @param minimumQuorumForProposals how many members must vote on a proposal for it to be executed
     * @param minimumMinutesForDebate the minimum amount of delay between when a proposal is made and when it can be executed
     * @param newPercentOfVotesForPassage the proposal needs to have 50% plus this number
     */
    function changeVotingRules(
        uint minimumQuorumForProposals,
        uint minimumMinutesForDebate,
        uint newPercentOfVotesForPassage
    ) onlyOwner public {
        require(newPercentOfVotesForPassage <= 100 && newPercentOfVotesForPassage >= 50);
        minimumQuorum = minimumQuorumForProposals;
        minDebatingPeriodInMinutes = minimumMinutesForDebate;
        percentOfVotesForPassage = newPercentOfVotesForPassage;

        ChangeOfRules(minimumQuorum, minDebatingPeriodInMinutes, percentOfVotesForPassage);
    }

    /**
     * Add Proposal
     *
     * Propose to send `weiAmountToSend / 1e18` ether to `transactionRecipient` for `proposalDescription`. `transactionBytecode ? Contains : Does not contain` code.
     *
     * @param transactionRecipient the person or smart-contract to send the ether and data to
     * @param weiAmountToSend amount of ether to send with the transaction, in wei
     * @param proposalDescription description of proposal
     * @param transactionBytecode bytecode of transaction
     */
    function newProposal(
        address transactionRecipient,
        uint weiAmountToSend,
        uint debatingPeriodInMinutes,
        string proposalDescription,
        bytes transactionBytecode,
        uint elevatedPassagePercent
    )
        onlyMembers public
        returns (uint proposalID)
    {
        require(congressActive);
        require(now > december25UTC + 6 hours);
        require(debatingPeriodInMinutes >= minDebatingPeriodInMinutes);
        proposalID = proposals.length++;
        Proposal storage p = proposals[proposalID];
        p.transactionRecipient = transactionRecipient;
        p.amount = weiAmountToSend;
        p.description = proposalDescription;
        p.proposalHash = keccak256(transactionRecipient, weiAmountToSend, transactionBytecode);
        p.votingDeadline = now + debatingPeriodInMinutes * 1 minutes;
        //p.executed = false;
        //p.proposalPassed = false;
        //p.proposalRejected = false;
        p.numberOfVotes = 0;
        if (elevatedPassagePercent > percentOfVotesForPassage && elevatedPassagePercent <= 100) {
            p.elevatedPassagePercent = elevatedPassagePercent;
        }
        ProposalAdded(proposalID, transactionRecipient, weiAmountToSend, debatingPeriodInMinutes, proposalDescription);
        numProposals = proposalID+1;

        return proposalID;
    }

    /**
     * Add proposal in Ether
     *
     * Propose to send `etherAmount` ether to `transactionRecipient` for `proposalDescription`. `transactionBytecode ? Contains : Does not contain` code.
     * This is a convenience function to use if the amount to be given is in round number of ether units.
     *
     * @param transactionRecipient who to send the ether to
     * @param etherAmount amount of ether to send
     * @param proposalDescription Description of proposal
     * @param transactionBytecode bytecode of transaction
     */
    function newProposalInEther(
        address transactionRecipient,
        uint etherAmount,
        uint debatingPeriodInMinutes,
        string proposalDescription,
        bytes transactionBytecode,
        uint elevatedPassagePercent
    )
        onlyMembers public
        returns (uint proposalID)
    {
        return newProposal(transactionRecipient, etherAmount * 1 ether, debatingPeriodInMinutes, proposalDescription, transactionBytecode, elevatedPassagePercent);
    }

    /**
     * Check if a proposal code matches
     *
     * @param proposalNumber ID number of the proposal to query
     * @param transactionRecipient who to send the ether to
     * @param weiAmount amount of ether to send
     * @param transactionBytecode bytecode of transaction
     */
    function checkProposalCode(
        uint proposalNumber,
        address transactionRecipient,
        uint weiAmount,
        bytes transactionBytecode
    )
        constant public
        returns (bool codeChecksOut)
    {
        Proposal storage p = proposals[proposalNumber];
        return p.proposalHash == keccak256(transactionRecipient, weiAmount, transactionBytecode);
    }

    /**
     * Log a vote for a proposal
     *
     * Vote `supportsProposal? in support of : against` proposal #`proposalNumber`
     *
     * @param proposalNumber number of proposal
     * @param supportsProposal either in favor or against it
     * @param justificationText optional justification text
     */
    function vote(
        uint proposalNumber,
        bool supportsProposal,
        string justificationText
    )
        onlyMembers public
        returns (uint voteID)
    {
        require(now > members[memberId[msg.sender]].memberSince + 200 seconds);
        Proposal storage p = proposals[proposalNumber];         // Get the proposal
        //require(now < p.votingDeadline);
        require(!p.voted[msg.sender]);                  // If has already voted, cancel
        p.voted[msg.sender] = true;                     // Set this voter as having voted
        p.numberOfVotes++;                              // Increase the number of votes
        if (supportsProposal) {                         // If they support the proposal
            p.yeas++;                          // Increase yeas
        } else {                                        // If they don't
            p.nays++;                         // Increase nays
            if (msg.sender == vetoPower) {  // putting here allow
                p.vetoed = true;
            } 
        }

        // Create a log of this event
        Voted(proposalNumber,  supportsProposal, msg.sender, justificationText);
        return p.numberOfVotes;
    }

    /**
     * Finish vote
     *
     * Count the votes proposal #`proposalNumber` and execute it if approved
     *
     * @param proposalNumber proposal number
     * @param transactionBytecode optional: if the transaction contained a bytecode, you need to send it
     */
    function executeProposal(uint proposalNumber, bytes transactionBytecode) public {
        Proposal storage p = proposals[proposalNumber];

        require(now > p.votingDeadline                                            // If it is past the voting deadline
            && !p.executed                                                         // and it has not already been executed
            && !p.proposalRejected                                                    // and it hasn't already failed an executeProposal attempt
            && p.proposalHash == keccak256(p.transactionRecipient, p.amount, transactionBytecode));  // and the supplied code matches the proposal

        uint percentToPass = percentOfVotesForPassage;
        if (p.elevatedPassagePercent > percentToPass) percentToPass = p.elevatedPassagePercent;

        // ...then execute result

        if ((100 * p.yeas >= percentToPass * p.numberOfVotes)                       // If proposal has vote percent needed
            && p.numberOfVotes >= minimumQuorum                                     // and a minimum quorum has been reached...
            && !(p.vetoed && 100*p.nays > 33*p.numberOfVotes)) {                    // and it hasn't been vetoed by the vetoPower with at least 33% nays

            // Proposal passed; execute the transaction
            p.executed = true; // Avoid recursive calling
            require(p.transactionRecipient.call.value(p.amount)(transactionBytecode));
            p.proposalPassed = true;
        } else {
            p.proposalRejected = true;
        }

        // Fire Events
        ProposalTallied(proposalNumber, 100 * p.yeas / p.numberOfVotes, p.numberOfVotes, p.proposalPassed);
    }

    /// @notice Destroy contract and send ether to `supersedingCongress`
    function selfDestruct() onlyOwner public {
        require(supersedingCongress != address(0));
        require(supersedingCongress != address(this));
        selfdestruct(supersedingCongress);
    }
}
