
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
    function balanceOfAt(address _user, uint256 id) external view virtual returns (uint256);
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
    bytes32 public constant VOTE_RAISER_ROLE = keccak256("VOTE_RAISER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE"); //whalegoddess
    
    uint256 public constant MAXIMUM_QUORUM_PERCENTAGE = 100;
    uint256 public constant MINIMUM_QUORUM_PERCENTAGE = 0;

    uint256 public constant MINIMUM_QUORUM_VOTERS = 1;
    
    ERC20Snapshottable public votingToken;
    
    mapping(address => bool) public enabledERC20Token;

    Quorum quorum = Quorum(50, 1200, 1);
    mapping(uint256 => Quorum) quorums;
    
    mapping(uint256 => VotingData) public voteContent;

    mapping(uint256 => mapping(address => bool)) voted;

    mapping(uint256 => uint256) public yay;
    mapping(uint256 => uint256) public yayCount;

    mapping(uint256 => uint256) public nay;
    mapping(uint256 => uint256) public nayCount;

    mapping(uint256 => uint256) public totalVotes;
    
    uint256 public voteRaisedIndex;
    mapping(uint256 => bool) public voteRaised;
    mapping(uint256 => VoteResult) public voteDecided;
    mapping(uint256 => bool) public voteResolved;
    
    bool paused;
    
    constructor(ERC20Snapshottable _votingToken) {
        _setupRole(OWNER_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(VOTE_RAISER_ROLE, msg.sender); 
        _setupRole(PAUSER_ROLE, msg.sender);
        votingToken = _votingToken;
    }
    
    event VoteRaised(VotingData data);
    function raiseVoteToSpendMATIC(address payable _receiver, uint256 _amount, string memory _voteTitle, string memory _voteContent) public onlyRole(VOTE_RAISER_ROLE) onlySender returns (uint256){
        require(address(this).balance >= _amount, "Not enough MATIC!");
        require(_amount > 0, "Send something1!");
        
        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            _amount,
            votingToken.snapshot(),
            VoteType.MATICSpend,
            address(0),
            quorum
        );
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        
        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    
    function raiseVoteToAddERC20Token(address payable _receiver, address _erc20Token, string memory _voteTitle, string memory _voteContent) public onlyRole(VOTE_RAISER_ROLE) onlySender returns (uint256) {
        require(!enabledERC20Token[_erc20Token], "Token already approved!");
        require(_erc20Token != address(0), "Pls use valid ERC20!");
        require(!paused, "Paused");

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
        
        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    
    function raiseVoteToSpendERC20Token(address payable _receiver, uint256 _amount, address _erc20Token, string memory _voteTitle, string memory _voteContent) public onlyRole(VOTE_RAISER_ROLE) onlySender returns (uint256){
        require(enabledERC20Token[_erc20Token], "Token not approved!");
        require(ERC20(_erc20Token).balanceOf(address(this)) > _amount, "Not enough MATIC!");
        require(_amount > 0, "Send something!");
        require(!paused, "Paused");

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
        
        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }

    function raiseVoteToUpdateQuorum(address payable _receiver, Quorum memory _newQuorum, string memory _voteTitle, string memory _voteContent) public onlyRole(VOTE_RAISER_ROLE) onlySender returns (uint256){
        require(!paused, "Paused");
        validateQuorum(_newQuorum);
        
        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            0,
            votingToken.snapshot(),
            VoteType.UpdateQuorum,
            address(0),
            _newQuorum
        );
        
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        voteRaised[voteRaisedIndex] = true;
        quorums[voteRaisedIndex] = quorum;
        
        emit VoteRaised(voteContent[voteRaisedIndex]);
        return voteRaisedIndex;
    }
    
    event Yay(VotingData data);
    event Nay(VotingData data);
    function vote(uint256 voteRaisedIndex, bool _yay) public onlySender {
        require(voteRaised[voteRaisedIndex], "vote not yet raised!");
        require(!voted[voteRaisedIndex][msg.sender], "Sender already voted");
        require(voteDecided[voteRaisedIndex] == VoteResult.VoteOpen, "vote already decided!");
        require(!paused, "Paused");
        
        uint256 balanceOf = votingToken.balanceOfAt(msg.sender, voteContent[voteRaisedIndex].snapshotId);
        require(balanceOf > 0, "No voting token!");
        
        if (_yay) {
            yay[voteRaisedIndex] += balanceOf;
            totalVotes[voteRaisedIndex] += balanceOf;
            yayCount[voteRaisedIndex] += 1;
        } else {
            nay[voteRaisedIndex] += balanceOf;
            totalVotes[voteRaisedIndex] += balanceOf;
            nayCount[voteRaisedIndex] += 1;
        }
        if (yay[voteRaisedIndex] * 100 > (quorums[voteRaisedIndex].quorumPercentage * totalVotes[voteRaisedIndex])
                && yay[voteRaisedIndex] > quorums[voteRaisedIndex].staticQuorumTokens
                && quorums[voteRaisedIndex].minVoters <= yayCount[voteRaisedIndex]) {
            emit Yay(voteContent[voteRaisedIndex]);
            voteDecided[voteRaisedIndex] = VoteResult.Passed;
        } else if ((nay[voteRaisedIndex] * 100 > (quorums[voteRaisedIndex].quorumPercentage * totalVotes[voteRaisedIndex]))
                && nay[voteRaisedIndex] > quorums[voteRaisedIndex].staticQuorumTokens
                && quorums[voteRaisedIndex].minVoters <= nayCount[voteRaisedIndex]) {
            emit Nay(voteContent[voteRaisedIndex]);
            voteDecided[voteRaisedIndex] = VoteResult.Discarded;
        }
        voted[voteRaisedIndex][msg.sender] = true;
        
        emit Voted(msg.sender, voteDecided[voteRaisedIndex]);
    }
    
    event Voted(address voter, VoteResult result);
    
    function resolveVote(uint256 voteRaisedIndex) public onlyRole(ADMIN_ROLE) {
        require(!paused, "Paused");
        require(voteDecided[voteRaisedIndex] != VoteResult.VoteOpen, "vote is still open!");
        require(!voteResolved[voteRaisedIndex], "Vote has already been resolved");

        if(voteDecided[voteRaisedIndex] == VoteResult.Discarded
                || voteDecided[voteRaisedIndex] == VoteResult.VetoedByOwner) {
            voteResolved[voteRaisedIndex] = true;
        } else if (voteDecided[voteRaisedIndex] == VoteResult.Passed 
                || voteDecided[voteRaisedIndex] == VoteResult.PassedByOwner ) {
            VotingData memory _data = voteContent[voteRaisedIndex];
            
            if (_data.voteType == VoteType.ERC20New) {
                enabledERC20Token[_data.erc20Token] = true;
            } else if (_data.voteType == VoteType.ERC20Spend) {
                ERC20(_data.erc20Token).transfer(_data.receiver, _data.amount);
            } else if (_data.voteType == VoteType.MATICSpend) {
                _data.receiver.transfer(_data.amount);
            } else if (_data.voteType == VoteType.UpdateQuorum) {
                quorum = _data.quorum;
            }
            voteResolved[voteRaisedIndex] = true;
        }
    }       
    
    
    function validateQuorum(Quorum memory _quorum) public {
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

    function ownerScrub(uint256 id, string memory _title, string memory _content) public onlyRole(OWNER_ROLE)  {
        voteContent[id].title = _title;
        voteContent[id].content = _content;
    }
    
    function setPaused(bool _paused) public onlyRole(PAUSER_ROLE) {
        paused = _paused;
    }
    
    function revokeVoteRaiser(address _newRaiser) public onlyRole(ADMIN_ROLE) onlySender {
        require(!paused, "Paused");
        revokeRole(VOTE_RAISER_ROLE, _newRaiser);
    }
    
    function addVoteRaiser(address _newRaiser) public onlyRole(ADMIN_ROLE) onlySender {
        require(!paused, "Paused");
        _setupRole(VOTE_RAISER_ROLE, _newRaiser);
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
