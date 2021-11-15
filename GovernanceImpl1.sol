pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

struct VotingData {
    string title;
    string content;
    
    address payable receiver;
    uint256 amount;
    
    VoteType voteType;
    address erc20Token;
    Quorum quorum;
}

struct Quorum {
    uint256 quorumPercentage;
    uint256 staticQuorumTokens;
}

enum VoteType {
    ERC20New, ERC20Spend, ETHSpend, UpdateQuorum
}

enum VoteResult {
    VoteOpen, Passed, VetoedByOwner, Discarded
}

contract OnChainGovernanceImpl is AccessControl, Ownable {
    using SafeMath for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VOTE_RAISER_ROLE = keccak256("VOTE_RAISER_ROLE");
    
    ERC20 public votingToken;

    Quorum quorum = Quorum(50, 1000000000000);
    
    mapping(address => bool) public enabledERC20Token;
    
    
    mapping(uint256 => VotingData) public voteContent;

    mapping(uint256 => uint256) public yay;
    mapping(uint256 => uint256) public nay;
    mapping(uint256 => uint256) public totalVotes;
    
    
    uint256 public voteRaisedIndex;
    mapping(uint256 => bool) public voteRaised;
    
    mapping(uint256 => VoteResult) public voteDecided;
    
    mapping(uint256 => bool) public voteResolved;



    
    constructor(ERC20 _votingToken) {
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(VOTE_RAISER_ROLE, msg.sender);
        votingToken = _votingToken;
    }
    
    
    function raiseVoteToSpendETH(address payable _receiver, uint256 _amount, string memory _voteTitle, string memory _voteContent) public onlyRole(VOTE_RAISER_ROLE) onlySender returns (uint256){
        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            _amount,
            VoteType.ETHSpend,
            address(0),
            quorum
        );
        emit VoteRaised(voteContent[voteRaisedIndex]);
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        return voteRaisedIndex;
    }
    
    function raiseVoteToAddERC20Token(address payable _receiver, uint256 _amount, address _erc20Token, string memory _voteTitle, string memory _voteContent) public onlyRole(VOTE_RAISER_ROLE) onlySender returns (uint256) {
        require(!enabledERC20Token[_erc20Token], "Token already approved!");

        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            _amount,
            VoteType.ERC20New,
            _erc20Token,
            quorum
        );
        emit VoteRaised(voteContent[voteRaisedIndex]);
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        return voteRaisedIndex;
    }
    
    function raiseVoteToSpendERC20Token(address payable _receiver, uint256 _amount, address _erc20Token, string memory _voteTitle, string memory _voteContent) public onlyRole(VOTE_RAISER_ROLE) onlySender returns (uint256){
        require(enabledERC20Token[_erc20Token], "Token not approved!");
        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            _amount,
            VoteType.ERC20Spend, //isERC20
            _erc20Token,
            quorum
        );
        emit VoteRaised(voteContent[voteRaisedIndex]);
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        return voteRaisedIndex;
    }

    function raiseVoteToUpdateQuorum(address payable _receiver, Quorum memory _newQuorum, uint256 _quorumStatic, string memory _voteTitle, string memory _voteContent) public onlyRole(VOTE_RAISER_ROLE) onlySender returns (uint256){
        voteRaisedIndex += 1;
        voteContent[voteRaisedIndex] = VotingData(
            _voteTitle,
            _voteContent,
            _receiver,
            0,
            VoteType.UpdateQuorum, //isERC20
            address(0),
            _newQuorum
        );
        emit VoteRaised(voteContent[voteRaisedIndex]);
        voteDecided[voteRaisedIndex] = VoteResult.VoteOpen;
        return voteRaisedIndex;
    }
    
    event VoteRaised(VotingData data);

    
    function vote(uint256 voteRaisedIndex, bool _yay) public onlySender {
        require(voteRaised[voteRaisedIndex], "vote not yet raised!");
        require(voteDecided[voteRaisedIndex] == VoteResult.VoteOpen, "vote already decided!");
        
        uint256 balanceOf = votingToken.balanceOf(msg.sender);
        require(balanceOf > 0, "No voting token!");
        
        
        if (_yay) {
            yay[voteRaisedIndex] += balanceOf;
            totalVotes[voteRaisedIndex] += balanceOf;
        } else {
            nay[voteRaisedIndex] += balanceOf;
            totalVotes[voteRaisedIndex] += balanceOf;
        }
        
        if (yay[voteRaisedIndex] > quorum.quorumPercentage * totalVotes[voteRaisedIndex]
                && yay[voteRaisedIndex] > quorum.staticQuorumTokens) {
            emit Yay(voteContent[voteRaisedIndex]);
            voteDecided[voteRaisedIndex] = VoteResult.Passed;
        } else if ((nay[voteRaisedIndex] > quorum.quorumPercentage * totalVotes[voteRaisedIndex])
                && nay[voteRaisedIndex] > quorum.staticQuorumTokens) {
            emit Nay(voteContent[voteRaisedIndex]);
            voteDecided[voteRaisedIndex] = VoteResult.Discarded;
        }
    
    }
    
    
    function resolveVote(uint256 voteRaisedIndex) public onlyRole(ADMIN_ROLE) {
        require(voteDecided[voteRaisedIndex] != VoteResult.VoteOpen, "vote is still open!");
        if(voteDecided[voteRaisedIndex] == VoteResult.Discarded) {
            voteResolved[voteRaisedIndex] = true;
        } else if (voteDecided[voteRaisedIndex] == VoteResult.VetoedByOwner) {
            voteResolved[voteRaisedIndex] = true;
        } else if (voteDecided[voteRaisedIndex] == VoteResult.Passed) {
            VotingData memory _data = voteContent[voteRaisedIndex];
            
            if (_data.voteType == VoteType.ERC20New) {
                enabledERC20Token[_data.erc20Token] = true;
            } else if (_data.voteType == VoteType.ERC20Spend) {
                ERC20(_data.erc20Token).transfer(_data.receiver, _data.amount);
            } else if (_data.voteType == VoteType.ETHSpend) {
                _data.receiver.transfer(_data.amount);
            } else if (_data.voteType == VoteType.UpdateQuorum) {
                quorum = _data.quorum;
            }
        }
    }       
    
    event Yay(VotingData data);
    event Nay(VotingData data);
    
    function ownerVeto(uint256 proposalIndex) public onlyOwner {
        require(voteRaised[proposalIndex], "vote not raised!");
        require(voteDecided[proposalIndex] == VoteResult.VoteOpen, "Vote not open!");
        
        voteDecided[proposalIndex] = VoteResult.VetoedByOwner;
    }
    
    function revokeVoteRaiser(address _newRaiser) public onlyRole(ADMIN_ROLE) onlySender {
        revokeRole(VOTE_RAISER_ROLE, _newRaiser);
    }
    
    function revokeAdmin(address _newAdmin) public onlyOwner onlySender {
        revokeRole(ADMIN_ROLE, _newAdmin);
    }
    
    function addVoteRaiser(address _newRaiser) public onlyRole(ADMIN_ROLE) onlySender {
        _setupRole(VOTE_RAISER_ROLE, _newRaiser);
    }
    
    function addAdmin(address _newAdmin) public onlyOwner onlySender {
        _setupRole(ADMIN_ROLE, _newAdmin);
    }
    
    modifier onlySender {
  require(msg.sender == tx.origin, "No smart contracts");
      _;
    }   
}
