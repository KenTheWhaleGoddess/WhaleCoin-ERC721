// SPDX-License-Identifier: None

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

struct VotingData {
    string title;
    string content;
    
    address payable receiver;
    uint256 amount;
    uint256 snapshotId;
    uint256 timestamp;
    
    VoteType voteType;
    address erc20Token;
    Quorum quorum;
    Fees fees;
    
    address[] targets;
    uint256[] values;
    bytes[] calldatas;    
}

interface ERC20 {
    function balanceOf(address _user) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}
interface ERC20Snapshottable is ERC20 {
    function snapshot() external returns(uint256);
    function balanceOfAt(address _user, uint256 _id) external view returns (uint256);

}


struct Quorum {
    uint256 quorumPercentage;
    uint256 staticQuorumTokens;
    uint256 minVoters;
}

struct Fees {
    uint256 min;
    uint256 percent;
    address recipient;
}

struct VoteLog {
    bool voted;
    bool vote;
    string justification;
}
enum VoteType {
    ERC20New, ERC20Spend, MATICSpend, UpdateQuorum, UpdateFees, ContractCall
}

enum VoteResult {
    VoteOpen, Passed, PassedByOwner, VetoedByOwner, Discarded
}

contract OnChainGovernanceImpl is AccessControl {
    using SafeMath for uint256;
    
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    address public constant ZEROES = address(0);
    
    address public owner;
    address public nextOwner;

    uint256 public constant MAXIMUM_FEE_PERCENTAGE = 100;
    uint256 public constant MINIMUM_FEE_PERCENTAGE = 0;
    
    uint256 public constant MAXIMUM_QUORUM_PERCENTAGE = 100;
    uint256 public constant MINIMUM_QUORUM_PERCENTAGE = 1;
    uint256 public constant MINIMUM_QUORUM_VOTERS = 1;
    uint256 public constant MINIMUM_TOKENS_TO_PARTICIPATE = .01 ether;

    uint256 public constant MINIMUM_MS_BETWEEN_VOTES_RAISED = 60 * 30 * 1000; //(2 blocks / second) * (60 seconds / minute) * (30 minutes)
    uint256 public constant MINIMUM_MS_BEFORE_VOTE_RESOLVED = 60 * 1000; //(2 blocks / second) * (60 seconds / minute) * (1 minutes)

    ERC20Snapshottable public votingToken;

    mapping(address => bool) public enabledERC20Token;

    Quorum public quorum = Quorum(50, 1200, 1);
    mapping(uint256 => Quorum) quorums;

    Fees public fee = Fees(.01 ether, 10, address(this));

    mapping(uint256 => VotingData) public voteContent;

    mapping(address => mapping(uint256 => VoteLog)) public votelog;

    mapping(uint256 => uint256) public yay;
    mapping(uint256 => uint256) public yayCount;

    mapping(uint256 => uint256) public nay;
    mapping(uint256 => uint256) public nayCount;

    mapping(uint256 => uint256) public totalVotes;
    
    uint256 public voteRaisedIndex;
    uint256 public lastVoteRaised = block.timestamp - MINIMUM_MS_BETWEEN_VOTES_RAISED;
    mapping(uint256 => bool) public voteRaised;
    mapping(uint256 => VoteResult) public voteDecided;
    mapping(uint256 => bool) public voteResolved;
    
    //pauser role state variables
    bool public paused;
    bool public buyingPaused;
    bool public pausingEnabled;

    constructor(address _votingToken) {
        owner = msg.sender;
        _setupRole(OWNER_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(MEMBER_ROLE, msg.sender); 
        _setupRole(PAUSER_ROLE, msg.sender);
        
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(ADMIN_ROLE, OWNER_ROLE);
        _setRoleAdmin(MEMBER_ROLE, OWNER_ROLE);
        _setRoleAdmin(PAUSER_ROLE, OWNER_ROLE);
        votingToken = ERC20Snapshottable(address(_votingToken));
        enabledERC20Token[address(_votingToken)] = true;
    }
    
    event VoteRaised(VotingData data);
    function proposeSpendMATIC(address payable _receiver, uint256 _amount, string memory _voteTitle, string memory _voteContent) public onlyRole(MEMBER_ROLE) onlySender returns (uint256){
        require(votingToken.balanceOf(msg.sender) >= fee.min, "Not enough of ERC20!");
        require(address(this).balance >= _amount, "Not enough MATIC!");
        require(_amount > 0, "Send something1!");
        require(!paused, "Paused");
        require(block.timestamp > (lastVoteRaised + MINIMUM_MS_BETWEEN_VOTES_RAISED), "Vote too soon!");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            _amount,
            votingToken.snapshot(),
            block.timestamp,
            VoteType.MATICSpend,
            ZEROES,
            quorum,
            fee,
            new address[](0),
            new uint256[](0),
            new bytes[](0)
        );

        uint256 percent = votingToken.balanceOf(msg.sender) / 100 * (fee.percent);
        uint256 rawFee = percent > fee.min ? percent : fee.min;
        votingToken.transferFrom(msg.sender, fee.recipient, rawFee);
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        lastVoteRaised = block.number;
        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    
    function proposeAddERC20Token(address payable _receiver, address _erc20Token, string memory _voteTitle, string memory _voteContent) public onlyRole(MEMBER_ROLE) onlySender returns (uint256) {
        require(votingToken.balanceOf(msg.sender) >= fee.min, "Not enough of Voting Token to raise vote!");
        require(!enabledERC20Token[_erc20Token], "Token already approved!");
        require(_erc20Token != address(0), "Pls use valid ERC20!");
        require(!paused, "Paused");
        require(block.timestamp > (lastVoteRaised + MINIMUM_MS_BETWEEN_VOTES_RAISED), "Vote too soon!");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            0,
            votingToken.snapshot(),
            block.timestamp,
            VoteType.ERC20New,
            _erc20Token,
            quorum,
            fee,
            new address[](0),
            new uint256[](0),
            new bytes[](0)
        );

        uint256 percent = votingToken.balanceOf(msg.sender) / 100 * (fee.percent);
        uint256 rawFee = percent > fee.min ? percent : fee.min;
        votingToken.transferFrom(msg.sender, fee.recipient, rawFee);
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        lastVoteRaised = block.number;

        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    
    function proposeSpendERC20Token(address payable _receiver, uint256 _amount, address _erc20Token, string memory _voteTitle, string memory _voteContent) public onlyRole(MEMBER_ROLE) onlySender returns (uint256){
        require(votingToken.balanceOf(msg.sender) >= fee.min, "Not enough of Voting Token to raise vote!");
        require(enabledERC20Token[_erc20Token], "Token not approved!");
        require(ERC20(_erc20Token).balanceOf(address(this)) >= _amount, "Not enough of ERC20!");
        require(_amount > 0, "Send something!");
        require(!paused, "Paused");
        require(block.timestamp > (lastVoteRaised + MINIMUM_MS_BETWEEN_VOTES_RAISED), "Vote too soon!");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            _amount,
            votingToken.snapshot(),
            block.timestamp,
            VoteType.ERC20Spend,
            _erc20Token,
            quorum,
            fee,
            new address[](0),
            new uint256[](0),
            new bytes[](0)
        );
        
        uint256 percent = votingToken.balanceOf(msg.sender) / 100 * (fee.percent);
        uint256 rawFee = percent > fee.min ? percent : fee.min;
        votingToken.transferFrom(msg.sender, fee.recipient, rawFee);
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        lastVoteRaised = block.number;

        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    function proposeUpdateQuorum(address payable _recipient, Quorum memory _newQuorum, string memory _voteTitle, string memory _voteContent) public onlyRole(MEMBER_ROLE) onlySender returns (uint256){
        require(votingToken.balanceOf(msg.sender) >= fee.min, "Not enough of ERC20!");
        validateQuorum(_newQuorum);
        require(!paused, "Paused");
        require(block.timestamp > (lastVoteRaised + MINIMUM_MS_BETWEEN_VOTES_RAISED), "Vote too soon!");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _recipient,
            0,
            votingToken.snapshot(),
            block.timestamp,
            VoteType.UpdateQuorum,
            ZEROES,
            _newQuorum,
            fee,
            new address[](0),
            new uint256[](0),
            new bytes[](0)
        );

        uint256 percent = votingToken.balanceOf(msg.sender) / 100 * (fee.percent);
        uint256 rawFee = percent > fee.min ? percent : fee.min;
        votingToken.transferFrom(msg.sender, fee.recipient, rawFee);
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        lastVoteRaised = block.number;

        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    
    
    function proposeUpdateFees(address payable _recipient, Fees memory _newFees, string memory _voteTitle, string memory _voteContent) public onlyRole(MEMBER_ROLE) onlySender returns (uint256){
        require(votingToken.balanceOf(msg.sender) >= fee.min, "Not enough of ERC20!");
        validateFees(_newFees);
        require(!paused, "Paused");
        require(block.timestamp > (lastVoteRaised + MINIMUM_MS_BETWEEN_VOTES_RAISED), "Vote too soon!");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _recipient,
            0,
            votingToken.snapshot(),
            block.timestamp,
            VoteType.UpdateFees,
            ZEROES,
            quorum,
            _newFees,
            new address[](0),
            new uint256[](0),
            new bytes[](0)
        );

        uint256 percent = votingToken.balanceOf(msg.sender) / 100 * (fee.percent);
        uint256 rawFee = percent > fee.min ? percent : fee.min;
        votingToken.transferFrom(msg.sender, fee.recipient, rawFee);
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        lastVoteRaised = block.number;

        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    function proposeContractCall(address payable _recipient, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory _voteTitle, string memory _voteContent) public onlyRole(MEMBER_ROLE) returns (uint256) {
        require(votingToken.balanceOf(msg.sender) >= fee.min, "Not enough of ERC20!");
        require(!paused, "Paused");
        require(block.timestamp > (lastVoteRaised + MINIMUM_MS_BETWEEN_VOTES_RAISED), "Vote too soon!");

        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _recipient,
            0,
            block.timestamp,
            votingToken.snapshot(),
            VoteType.UpdateQuorum,
            ZEROES,
            quorum,
            fee,
            targets,
            values,
            calldatas
        );

        uint256 percent = votingToken.balanceOf(msg.sender) / 100 * (fee.percent);
        uint256 rawFee = percent > fee.min ? percent : fee.min;
        votingToken.transferFrom(msg.sender, fee.recipient, rawFee);
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        lastVoteRaised = block.number;
        
        return voteRaisedIndex;
    }    
    event Yay(VotingData data);
    event Nay(VotingData data);
    event Voted(address voter, VoteResult result, string justification);

    function vote(uint256 id, bool _yay, string memory justification) public onlySender onlyRole(MEMBER_ROLE){
        uint256 balanceOf = votingToken.balanceOfAt(msg.sender, voteContent[id].snapshotId);
        require(balanceOf >= MINIMUM_TOKENS_TO_PARTICIPATE, "Not enough of Voting token to vote. Need .01");
        require(voteRaised[id], "vote not yet raised!");
        require(!votelog[msg.sender][id].voted, "Sender already voted");
        require(!paused, "Paused");
        require(owner != address(this), "governance cannot vote")
        
        if (_yay) {
            yay[id] += balanceOf;
            totalVotes[id] += balanceOf;
            yayCount[id] += 1;
        } else {
            nay[id] += balanceOf;
            totalVotes[id] += balanceOf;
            nayCount[id] += 1;
        }
        if (yay[id] * 100 > (quorums[id].quorumPercentage * totalVotes[id])
                && yay[id] > quorums[id].staticQuorumTokens
                && quorums[id].minVoters <= yayCount[id]){
            emit Yay(voteContent[id]);
            voteDecided[id] = VoteResult.Passed;
        } else if ((nay[id] * 100 > (quorums[id].quorumPercentage * totalVotes[id]))
                && nay[id] > quorums[id].staticQuorumTokens
                && quorums[id].minVoters <= nayCount[id]) {
            emit Nay(voteContent[id]);
            voteDecided[id] = VoteResult.Discarded;
        }
        votelog[msg.sender][id].voted = true;
        votelog[msg.sender][id].vote = _yay;
        votelog[msg.sender][id].justification = justification;
        
        emit Voted(msg.sender, voteDecided[id], justification);
    }
    
    event VoteResolved(address _user, uint256 id);
    
    function resolveVote(uint256 id) public onlyRole(ADMIN_ROLE) {
        require(!paused, "Paused");
        require(voteDecided[id] != VoteResult.VoteOpen, "vote is still open!");
        require(!voteResolved[id], "Vote has already been resolved");
        require(voteContent[id].timestamp + MINIMUM_MS_BEFORE_VOTE_RESOLVED < block.timestamp, "Need to wait to resolve");

        if(voteDecided[id] == VoteResult.Discarded
                || voteDecided[id] == VoteResult.VetoedByOwner) {
            voteResolved[id] = true;
        } else if (voteDecided[id] == VoteResult.Passed 
                || voteDecided[id] == VoteResult.PassedByOwner) {
            VotingData memory _data = voteContent[id];
            
            if (_data.voteType == VoteType.ERC20New) {
                enabledERC20Token[_data.erc20Token] = true;
            } else if (_data.voteType == VoteType.ERC20Spend) {
                ERC20(_data.erc20Token).transfer(_data.receiver, _data.amount);
            } else if (_data.voteType == VoteType.MATICSpend) {
                _data.receiver.transfer(_data.amount);
            } else if (_data.voteType == VoteType.UpdateQuorum) {
                quorum = _data.quorum;
            } else if (_data.voteType == VoteType.UpdateFees) {
                fee = _data.fees;
            } else if (_data.voteType == VoteType.ContractCall) {
                _execute(_data.targets, _data.values, _data.calldatas);
            }
            emit VoteResolved(msg.sender, id);
            voteResolved[id] = true;
        }
    }       
    event ContractCallExecuted(bool success, bytes returndata);
    function _execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal virtual {
        string memory errorMessage = "Governor: call reverted without message";
        for (uint256 i = 0; i < targets.length; ++i) {
            (bool success, bytes memory returndata) = targets[i].call{value: values[i]}(calldatas[i]);
            Address.verifyCallResult(success, returndata, errorMessage);
            emit ContractCallExecuted(success, returndata);
        }
    }

    function validateQuorum(Quorum memory _quorum) internal pure {
        require(_quorum.quorumPercentage <= MAXIMUM_QUORUM_PERCENTAGE
            && _quorum.quorumPercentage >= MINIMUM_QUORUM_PERCENTAGE, "Quorum Percentage out of 0-100");
            
        require(_quorum.minVoters >= MINIMUM_QUORUM_VOTERS, "Quorum requires 1 voter");
    }

    function validateFees(Fees memory _fees) internal pure {
        require(_fees.percent <= MAXIMUM_FEE_PERCENTAGE
            && _fees.percent >= MINIMUM_FEE_PERCENTAGE, "Quorum Percentage out of 0-100");
    }
    event Veto(uint256 id);
    event ForcePass(uint256 id);  
    
    function ownerVetoProposal(uint256 proposalIndex) public onlyRole(OWNER_ROLE) {
        require(voteRaised[proposalIndex], "vote not raised!");
        require(!voteResolved[proposalIndex], "Vote resolved!");
        require(owner != address(this), "when self governed, veto is disabled");

        voteDecided[proposalIndex] = VoteResult.VetoedByOwner;
        emit Veto(proposalIndex);
    }
    
    function ownerPassProposal(uint256 proposalIndex) public onlyRole(OWNER_ROLE)  {
        require(voteRaised[proposalIndex], "vote not raised!");
        require(!voteResolved[proposalIndex], "Vote resolved!");
        require(owner != address(this), "when self governed, owner pass is disabled");
        
        voteDecided[proposalIndex] = VoteResult.PassedByOwner;
        emit ForcePass(proposalIndex);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        paused = true;
    }
    function unpause() public onlyRole(PAUSER_ROLE) {
        paused = false;
    }

    function pauseBuying() public onlyRole(PAUSER_ROLE) {
        buyingPaused = true;
    }
    function unpauseBuying() public onlyRole(PAUSER_ROLE) {
        buyingPaused = false;
    }
    
    event MemberAdded(address _user, address _admin);
    event MemberRevoked(address _user, address _admin);
    function revokeMember(address _newRaiser) public onlyRole(ADMIN_ROLE) onlySender {
        require(!paused, "Paused");
        revokeRole(MEMBER_ROLE, _newRaiser);
        emit MemberRevoked(_newRaiser, msg.sender);
    }
    
    function addMember(address _newRaiser) public onlyRole(ADMIN_ROLE) onlySender {
        require(!paused, "Paused");
        _setupRole(MEMBER_ROLE, _newRaiser);
        emit MemberAdded(_newRaiser, msg.sender);
    }
    
    function promoteNextOwner(address _nextOwner) public onlyRole(OWNER_ROLE) {
        require(_nextOwner != owner, "next owner == owner");
        require(_nextOwner != ZEROES, "Must promote valid governance");
        require(owner != address(this), "when self governed, ownership changing is disabled");

        nextOwner = _nextOwner;   
    }
    event OwnershipTransferred(address _old, address _new);
    function acceptOwnership() public onlyRole(MEMBER_ROLE) {
        require(msg.sender != owner, "Owner cannot take own ownership");
        require(nextOwner == msg.sender, "Caller not nominated");
        
        _setupRole(OWNER_ROLE, msg.sender);
        revokeRole(OWNER_ROLE, owner);
        
        //emit event before updating state vars
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        nextOwner = ZEROES;
    }
    
    modifier onlySender {
      require(msg.sender == tx.origin, "No smart contracts");
      _;
    }
    

    event Received(address from, uint amount);
    receive() external payable {
        if (msg.value > 0)
            emit Received(msg.sender, msg.value);
    }
    
    fallback() external payable {
        if (msg.value > 0)
            emit Received(msg.sender, msg.value);
    }
}
