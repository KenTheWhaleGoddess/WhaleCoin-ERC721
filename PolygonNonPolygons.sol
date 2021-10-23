//"SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "github.com/Arachnid/solidity-stringutils/strings.sol";

contract PolygonNonPolygons is ERC721, Ownable {
    using strings for *;
    uint256 public tokenCounter;

    uint256 public _salePrice = 5000000000000; // .005TH

    uint256 private _maxPerTx = 1001; // Set to one higher than actual, to save gas on <= checks.

    uint256 public _totalSupply = 33000;
    


    string private _baseTokenURI;
    bool private _saleState;

    mapping(uint256 => uint256[]) tokenIdToInputString;
    

    constructor () ERC721 ("Lets Buy a Noun","IWANT")  {
        tokenCounter = 0;
        _saleState = false;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string inputString = tokenIdToInputString[tokenId];
        return string(abi.encodePacked(getBaseURI(), inputString));
    }
    
    function createCollectible(string memory) private {
            _safeMint(msg.sender, tokenCounter);
            tokenIdToInputString[tokenCounter] = memory;
            tokenCounter = tokenCounter + 1;
    }
    
    function maxMintsPerTransaction() public view returns (uint) {
        return _maxPerTx - 1; //_maxPerTx is off by 1 for require checks in HOF Mint. Allows use of < instead of <=, less gas
    }

    function isSaleOpen() public view returns (bool) {
        return _saleState && !isSaleComplete();
    }

    function isSaleComplete() public view returns (bool) {
        return tokenCounter == _totalSupply;
    }
    
    function getSaleState() private view returns (bool){
        return _saleState;
    }
    
    function setSaleState(bool saleState) public onlyOwner {
        _saleState = saleState;
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
        require(payable(msg.sender).send(address(this).balance));
    }
}
