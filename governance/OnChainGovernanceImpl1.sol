
// SPDX-License-Identifier: None

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

struct VotingData {
    string title;
    string content;
    
    address payable receiver;
    uint256 amount;
    uint256 snapshotId;
    
    VoteType voteType;
    address erc20Token;
    Quorum quorum;
}

interface ERC20Snapshottable {
    function snapshot() external returns(uint256);
    function balanceOfAt(address _user, uint256 id) external view returns (uint256);
}

struct Quorum {
    uint256 quorumPercentage;
    uint256 staticQuorumTokens;
    uint256 minVoters;
}

enum VoteType {
    ERC20New, ERC20Spend, MATICSpend, UpdateQuorum
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
    
    uint256 public constant MAXIMUM_QUORUM_PERCENTAGE = 100;
    uint256 public constant MINIMUM_QUORUM_PERCENTAGE = 1;
    uint256 public constant MINIMUM_QUORUM_VOTERS = 1;

    uint256 public constant MINIMUM_BLOCKS_BETWEEN_VOTES = 2; //* 60 * 30; //(2 blocks / second) * (60 seconds / minute) * (30 minutes)

    ERC20Snapshottable public votingToken;
    
    mapping(address => bool) public enabledERC20Token;

    Quorum public quorum = Quorum(50, 1200, 1);
    mapping(uint256 => Quorum) quorums;
    
    mapping(uint256 => VotingData) public voteContent;

    mapping(address => mapping(uint256 => bool)) voted;
    mapping(address => mapping(uint256 => string)) justifications;

    mapping(uint256 => uint256) public yay;
    mapping(uint256 => uint256) public yayCount;

    mapping(uint256 => uint256) public nay;
    mapping(uint256 => uint256) public nayCount;

    mapping(uint256 => uint256) public totalVotes;
    
    uint256 public voteRaisedIndex;
    uint256 public lastVoteRaised = block.number - MINIMUM_BLOCKS_BETWEEN_VOTES;
    mapping(uint256 => bool) public voteRaised;
    mapping(uint256 => VoteResult) public voteDecided;
    mapping(uint256 => bool) public voteResolved;
    
    bool public paused;
    
    constructor(ERC20Snapshottable _votingToken) {
        owner = msg.sender;
        _setupRole(OWNER_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(MEMBER_ROLE, msg.sender); 
        _setupRole(PAUSER_ROLE, msg.sender);
        
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(ADMIN_ROLE, OWNER_ROLE);
        _setRoleAdmin(MEMBER_ROLE, OWNER_ROLE);
        _setRoleAdmin(PAUSER_ROLE, OWNER_ROLE);
        votingToken = _votingToken;
    }
    
    event VoteRaised(VotingData data);
    function raiseVoteToSpendMATIC(address payable _receiver, uint256 _amount, string memory _voteTitle, string memory _voteContent) public onlyRole(MEMBER_ROLE) onlySender returns (uint256){
        require(address(this).balance >= _amount, "Not enough MATIC!");
        require(_amount > 0, "Send something1!");
        require(!paused, "Paused");
        require(block.number >(lastVoteRaised + MINIMUM_BLOCKS_BETWEEN_VOTES), "Vote too soon!");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            _amount,
            votingToken.snapshot(),
            VoteType.MATICSpend,
            ZEROES,
            quorum
        );
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        lastVoteRaised = block.number;
        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    
    function raiseVoteToAddERC20Token(address payable _receiver, address _erc20Token, string memory _voteTitle, string memory _voteContent) public onlyRole(MEMBER_ROLE) onlySender returns (uint256) {
        require(!enabledERC20Token[_erc20Token], "Token already approved!");
        require(_erc20Token != address(0), "Pls use valid ERC20!");
        require(!paused, "Paused");
        require(block.number >(lastVoteRaised + MINIMUM_BLOCKS_BETWEEN_VOTES), "Vote too soon!");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            0,
            votingToken.snapshot(),
            VoteType.ERC20New,
            _erc20Token,
            quorum
        );
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        lastVoteRaised = block.number;

        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    
    function raiseVoteToSpendERC20Token(address payable _receiver, uint256 _amount, address _erc20Token, string memory _voteTitle, string memory _voteContent) public onlyRole(MEMBER_ROLE) onlySender returns (uint256){
        require(enabledERC20Token[_erc20Token], "Token not approved!");
        require(ERC20(_erc20Token).balanceOf(address(this)) > _amount, "Not enough of ERC20!");
        require(_amount > 0, "Send something!");
        require(!paused, "Paused");
        require(block.number >(lastVoteRaised + MINIMUM_BLOCKS_BETWEEN_VOTES), "Vote too soon!");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            _amount,
            votingToken.snapshot(),
            VoteType.ERC20Spend,
            _erc20Token,
            quorum
        );
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        lastVoteRaised = block.number;

        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }

    function raiseVoteToUpdateQuorum(address payable _receiver, Quorum memory _newQuorum, string memory _voteTitle, string memory _voteContent) public onlyRole(MEMBER_ROLE) onlySender returns (uint256){
        validateQuorum(_newQuorum);
        require(!paused, "Paused");
        require(block.number >(lastVoteRaised + MINIMUM_BLOCKS_BETWEEN_VOTES), "Vote too soon!");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            0,
            votingToken.snapshot(),
            VoteType.UpdateQuorum,
            ZEROES,
            _newQuorum
        );
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        lastVoteRaised = block.number;

        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    
    event Yay(VotingData data);
    event Nay(VotingData data);
    
    function vote(uint256 id, bool _yay, string memory justification) public onlySender onlyRole(MEMBER_ROLE){
        require(voteRaised[id], "vote not yet raised!");
        require(!voted[msg.sender][id], "Sender already voted");
        require(voteDecided[id] == VoteResult.VoteOpen, "vote already decided!");
        require(!paused, "Paused");
        
        uint256 balanceOf = votingToken.balanceOfAt(msg.sender, voteContent[id].snapshotId);
        require(balanceOf > 0, "No voting token!");
        
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
                && quorums[id].minVoters <= yayCount[id]) {
            emit Yay(voteContent[id]);
            voteDecided[id] = VoteResult.Passed;
        } else if ((nay[id] * 100 > (quorums[id].quorumPercentage * totalVotes[id]))
                && nay[id] > quorums[id].staticQuorumTokens
                && quorums[id].minVoters <= nayCount[id]) {
            emit Nay(voteContent[id]);
            voteDecided[id] = VoteResult.Discarded;
        }
        voted[msg.sender][id] = true;
        justifications[msg.sender][id] = justification;
        
        emit Voted(msg.sender, voteDecided[id], justification);
    }
    
    event Voted(address voter, VoteResult result, string justification);
    
    function resolveVote(uint256 id) public onlyRole(ADMIN_ROLE) {
        require(!paused, "Paused");
        require(voteDecided[id] != VoteResult.VoteOpen, "vote is still open!");
        require(!voteResolved[id], "Vote has already been resolved");

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
            }
            voteResolved[id] = true;
        }
    }       
    
    
    function validateQuorum(Quorum memory _quorum) internal pure {
        require(_quorum.quorumPercentage <= MAXIMUM_QUORUM_PERCENTAGE
            && _quorum.quorumPercentage >= MINIMUM_QUORUM_PERCENTAGE, "Quorum Percentage out of 0-100");
            
        require(_quorum.minVoters >= MINIMUM_QUORUM_VOTERS, "Quorum requires 1 voter");
    }

    event Veto(uint256 id);
    event ForcePass(uint256 id);
    
    function ownerVetoProposal(uint256 proposalIndex) public onlyRole(OWNER_ROLE) {
        require(voteRaised[proposalIndex], "vote not raised!");
        require(!voteResolved[proposalIndex], "Vote resolved!");
        
        voteDecided[proposalIndex] = VoteResult.VetoedByOwner;
        emit Veto(proposalIndex);
    }
    
    function ownerPassProposal(uint256 proposalIndex) public onlyRole(OWNER_ROLE)  {
        require(voteRaised[proposalIndex], "vote not raised!");
        require(!voteResolved[proposalIndex], "Vote resolved!");
        
        voteDecided[proposalIndex] = VoteResult.PassedByOwner;
        emit ForcePass(proposalIndex);
    }

    function setPaused(bool _paused) public onlyRole(PAUSER_ROLE) {
        paused = _paused;
    }
    
    function revokeMember(address _newRaiser) public onlyRole(ADMIN_ROLE) onlySender {
        require(!paused, "Paused");
        revokeRole(MEMBER_ROLE, _newRaiser);
    }
    
    function addMember(address _newRaiser) public onlyRole(ADMIN_ROLE) onlySender {
        require(!paused, "Paused");
        _setupRole(MEMBER_ROLE, _newRaiser);
    }
    
    function promoteNextOwner(address _nextOwner) public onlyRole(OWNER_ROLE) {
        require(_nextOwner != owner, "next owner == owner");
        require(_nextOwner != ZEROES, "Must promote valid governance");
        nextOwner = _nextOwner;   
    }
    
    function acceptOwnership() public onlyRole(MEMBER_ROLE) {
        require(msg.sender != owner, "Owner cannot take own ownership");
        require(nextOwner == msg.sender, "Caller not nominated");
        
        _setupRole(OWNER_ROLE, msg.sender);
        revokeRole(OWNER_ROLE, owner);
        owner = msg.sender;

        nextOwner = ZEROES;
    }
    
    modifier onlySender {
      require(msg.sender == tx.origin, "No smart contracts");
      _;
    }
    
    event Received(address from, uint amount);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
    
    fallback() external payable {
        emit Received(msg.sender, msg.value);
    }
}
