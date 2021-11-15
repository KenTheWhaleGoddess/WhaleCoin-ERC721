// SPDX-License-Identifier: None
pragma solidity ^0.8.7;

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

interface OnChainGovernance {
    
    event VoteRaised(VotingData data);
    function raiseVoteToSpendMATIC(address payable _receiver, uint256 _amount, string memory _voteTitle, string memory _voteContent) external returns (uint256);
    function raiseVoteToAddERC20Token(address payable _receiver, address _erc20Token, string memory _voteTitle, string memory _voteContent) external returns (uint256);
    function raiseVoteToSpendERC20Token(address payable _receiver, uint256 _amount, address _erc20Token, string memory _voteTitle, string memory _voteContent) external returns (uint256);
    
    function raiseVoteToUpdateQuorum(address payable _receiver, Quorum memory _newQuorum, string memory _voteTitle, string memory _voteContent) external returns (uint256);
    

    event Yay(VotingData data);
    event Nay(VotingData data);
    function vote(uint256 voteRaisedIndex, bool _yay, string memory justification) external;
    function resolveVote(uint256 voteRaisedIndex) external;

    event Veto(uint256 id);
    event ForcePass(uint256 id);
    function ownerVetoProposal(uint256 proposalIndex) external;
    function ownerPassProposal(uint256 proposalIndex) external;


}
