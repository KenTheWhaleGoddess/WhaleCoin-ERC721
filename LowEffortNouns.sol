//"SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/*
* $$$$$$$\                            $$$$$$$\                      $$\       
* $$  __$$\                           $$  __$$\                     $$ |      
* $$ |  $$ |$$\   $$\ $$\   $$\       $$ |  $$ |$$\   $$\ $$$$$$$\  $$ |  $$\ 
* $$$$$$$\ |$$ |  $$ |$$ |  $$ |      $$$$$$$  |$$ |  $$ |$$  __$$\ $$ | $$  |
* $$  __$$\ $$ |  $$ |$$ |  $$ |      $$  ____/ $$ |  $$ |$$ |  $$ |$$$$$$  / 
* $$ |  $$ |$$ |  $$ |$$ |  $$ |      $$ |      $$ |  $$ |$$ |  $$ |$$  _$$<  
* $$$$$$$  |\$$$$$$  |\$$$$$$$ |      $$ |      \$$$$$$  |$$ |  $$ |$$ | \$$\ 
* \_______/  \______/  \____$$ |      \__|       \______/ \__|  \__|\__|  \__|
*                     $$\   $$ |                                              
*                     \$$$$$$  |                                              
*                      \______/             -> https://opensea.io/collection/low-effort-punks                                 
*                                            - LamboWhale & WhaleGoddess
*/

/* Thanks to Nouns DAO for the inspiration. nouns.wtf */

contract SimpleCollectible is ERC721, Ownable {
    using SafeMath for uint256;
    uint256 public tokenCounter;

    uint256 private _salePrice = .01 ether; // .01 ETH

    uint256 private _maxPerTx = 70; // Set to one higher than actual, to save gas on <= checks.

    uint256 public _totalSupply = 5635; 

    string private _baseTokenURI;
    bool private paused; 
    
    address private WG = 0x1B3FEA07590E63Ce68Cb21951f3C133a35032473;
    address private LW = 0x01e0d267E922C33469a97ec60753f93C6A4C15Ff;
    
    constructor () ERC721 ("Low Effort Nouns","LEN")  {
        setBaseURI("https://gateway.pinata.cloud/ipfs/QmYtC928MTEf5bksypYYejwrV6xMHaA6ZubfzR3tmW2GC9");
        tokenCounter = 0;
        paused = true;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return string(abi.encodePacked(getBaseURI(), Strings.toString(tokenId), ".json"));
    }
    function mintCollectibles(uint256 _count) public payable {
        require(!paused, "Sale is not yet open");
        require(_count < _maxPerTx, "Cant mint more than mintMax");
        require((_count + tokenCounter) <= _totalSupply, "Ran out of NFTs for sale! Sry!");
        require(msg.value >= (_salePrice * _count), "Ether value sent is not correct");

        createCollectibles(msg.sender, _count);
    }

	function mintWithWGPass(address _user) public {
	    require(msg.sender == address(0x1B7c412E7D83Daf1Bf13bb0DbAc471C71AfaC9af), "Only the mint pass contract may call this function");
        require((1 + tokenCounter) <= _totalSupply, "Ran out of NFTs for sale! Sry!");
        
        createCollectibles(_user, 1);
	}

    function ownerMint(uint256 _count, address _user) public onlyOwner {
        require((_count + tokenCounter) <= _totalSupply, "Ran out of NFTs for presale! Sry!");

        createCollectibles(_user, _count);
    }

    function createCollectibles(address _user, uint256 _count) private {
        for(uint i = 0; i < _count; i++) {
            createCollectible(_user);
        }
    }

    function createCollectible(address _user) private {
            _safeMint(_user, tokenCounter);
            tokenCounter = tokenCounter + 1;
    }
    
    function maxMintsPerTransaction() public view returns (uint) {
        return _maxPerTx - 1; //_maxPerTx is off by 1 for require checks in HOF Mint. Allows use of < instead of <=, less gas
    }

    function isSaleComplete() public view returns (bool) {
        return tokenCounter == _totalSupply;
    }
    function toggleSaleState() public onlyOwner {
        paused = !paused;
    }
    
    function getSalePrice() private view returns (uint){
        return _salePrice;
    }
    
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    function getBaseURI() public view returns (string memory){
        return _baseTokenURI;
    }
    function withdrawAll() public payable onlyOwner {
        uint256 bal = address(this).balance;
        payable(WG).transfer(bal.div(100).mul(5));
        payable(LW).transfer(address(this).balance);
    }
}
