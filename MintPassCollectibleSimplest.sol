//"SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract SimpleCollectible is ERC721, Ownable {
    uint256 public tokenCounter;

    uint256 public _totalSupply = 100; 

    string private _baseTokenURI;

    // Faciliating the needed functionality for the presale
    mapping(address => bool) addressToPreSaleEntry;
    
    constructor () ERC721 ("Random Spookies","RAND")  {
        tokenCounter = 0;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        return string(abi.encodePacked(getBaseURI(), Strings.toString(tokenId)));
    }

	function mintWithWGPass(address _user) public {
	    require(msg.sender == address(0xDF47D84787c4607Ad3c7034D2b238Beec2B0cf49), "Only the mint pass contract may call this function");
        require((1 + tokenCounter) <= _totalSupply, "Ran out of NFTs for sale! Sry!");
        
        createCollectible(_user);
	}

    function createCollectible(address _user) private {
            _safeMint(_user, tokenCounter);
            tokenCounter = tokenCounter + 1;
    }
    
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    function getBaseURI() public view returns (string memory){
        return _baseTokenURI;
    }
}
