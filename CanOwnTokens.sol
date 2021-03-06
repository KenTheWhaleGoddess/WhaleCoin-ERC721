
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Base64.sol";

contract NFTsThatCanOwnTokens is ERC721, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  using Strings for uint256;
  uint256 counter;

  mapping(uint256 => mapping(ERC20 => uint256)) balances;
  mapping(uint256 => EnumerableSet.AddressSet) tokensInNFT;
  mapping(ERC20 => bool) approvedTokens;    
  mapping(address => bool) frens;
  constructor() ERC721("NFT Cash Card V1", "$$$") {
    frens[msg.sender] = true;
  }

  modifier onlyOwnerOf(uint256 tokenId) {
    require(_exists(tokenId), "Token not in existence");
    require(_isApprovedOrOwner(msg.sender, tokenId), "Token not owned by caller");
    _;
  }

  modifier onlyFrens() {
    require(frens[msg.sender], "not a fren");
    _;
  }

  modifier approvedToken(ERC20 token) {
    require(approvedTokens[token], "Not approved");
    _;
  }

  // public
  function mint(uint256 _count) public {
    require(counter + _count <= 1000);
    require(_count < 11, "10 is the max at a time");

    for(uint256 i = 0; i < _count; i++) {
      _safeMint(msg.sender, counter + i);
    }
    counter += _count;
  }

  function sendToNFT(uint256 tokenId, ERC20 token, uint256 amount) nonReentrant approvedToken(token) public {
    require(token.allowance(msg.sender, address(this)) >= amount, "Not approved to spend");
    
    token.transferFrom(msg.sender, address(this), amount);
    if(balances[tokenId][token] == 0) { //add to set
      tokensInNFT[tokenId].add((address(token)));
    }
    balances[tokenId][token] += amount;
  }
  function withdrawFromNFT(uint256 tokenId, ERC20 token, uint256 amount) public approvedToken(token) onlyOwnerOf(tokenId) {
    require(balances[tokenId][token] >= amount, "not enough to withdraw that");
    require(amount > 0, "cannot withdraw nothing");
    token.transfer(msg.sender, amount);
    balances[tokenId][token] -= amount;
    if(balances[tokenId][token] == 0) { //add to set
      tokensInNFT[tokenId].remove((address(token)));
    }
  }
  
  function balanceOfAt(uint256 tokenId, ERC20 token) public view returns (uint256) {
    return balances[tokenId][token];
  }

    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        require(_exists(tokenId),"ERC721Metadata: URI query for nonexistent token");
        string memory parts;
        parts = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="0x542B72"/><text x="10" y="20" class="base">';

        for (uint256 i = 0; i < tokensInNFT[tokenId].length(); i++) {
          ERC20 token = ERC20(tokensInNFT[tokenId].at(i));
          parts = string(abi.encodePacked(parts, "balance is ", (balances[tokenId][token] / token.decimals()).toString(), " ", token.symbol(), '</text><text x="10" y="40" class="base">'));
        }

        string memory output = string(abi.encodePacked(parts, '</text></svg>'));

        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "NFT Cash Card #', tokenId.toString(), ' (V1)", "description": "This NFT cash card is a fully on-chain representation of assets managed by the NFT smart contract. NFTs have balances, can be withdrawn from by the owner. It currently holds ', tokensInNFT[tokenId].length().toString(), ' types of ERC20s. It is made as a free mint to demonstrate NFT Utility.", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '"}'))));
        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }

  function toggleApprovedToken(ERC20 token) public onlyFrens {
    approvedTokens[token] = !approvedTokens[token];
  }

  function toggleFren(address _fren) public onlyOwner {
    frens[_fren] = !frens[_fren];
  }
  function isFren(address _fren) public view returns (bool) {
    return frens[_fren];
  }
}
