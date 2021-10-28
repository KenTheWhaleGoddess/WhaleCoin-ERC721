//"SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ICollectible is IERC721 {
	function mintWithWGPass(address _user) external;
} 

contract MintPass is ERC721, Ownable {
    uint256 public tokenCounter;

    uint256 private _salePrice = 50000000000000000; // .05 ETH

    uint256 private _maxPerTx = 6; // Set to one higher than actual, to save gas on <= checks.

    uint256 public _totalSupply = 100; 

    string private _baseTokenURI;
    uint private _saleState; // 0 - No sale. 1 - Main Sale.

    // Faciliating the needed functionality for the Mint Pass
    mapping(ICollectible => bool) trustedCollectibles;
    mapping(ICollectible => mapping(uint256 => bool)) mintClaimed;

    constructor () ERC721 ("WhaleGoddess Mint Pass","WGMP")  {
        tokenCounter = 0;
        _saleState = 0;
    }
    
    function addTrustedCollectible(ICollectible collectible) public onlyOwner {
        trustedCollectibles[collectible] = true;
    }
    
    function mintTrustedCollectible(ICollectible collectible) public {
        require(trustedCollectibles[collectible], "untrusted collectible");
        for(uint256 i = 0; i < _totalSupply; i++) {
            if(msg.sender == ownerOf(i) && !mintClaimed[collectible][i]) {
                collectible.mintWithWGPass(msg.sender);
                mintClaimed[collectible][i] = true;
            }
        }
    }

    function mint(uint256 _count) public payable {
        require(isSaleOpen(), "Sale is not yet open");
        require(_count < _maxPerTx, "Cant mint more than mintMax");
        require((_count + tokenCounter) <= _totalSupply, "Ran out of NFTs for sale! Sry!");
        require(msg.value >= (_salePrice * _count), "Ether value sent is not correct");

        createCollectibles(_count);
    }

    function ownerMint(uint256 _count) public onlyOwner {
        require((_count + tokenCounter) <= _totalSupply, "Ran out of NFTs for presale! Sry!");

        createCollectibles(_count);
    }
    function createCollectibles(uint256 _count) private {
        for(uint i = 0; i < _count; i++) {
            createCollectible();
        }
    }

    function createCollectible() private {
            _safeMint(msg.sender, tokenCounter);
            tokenCounter = tokenCounter + 1;
    }
    
    function maxMintsPerTransaction() public view returns (uint) {
        return _maxPerTx - 1; //_maxPerTx is off by 1 for require checks in HOF Mint. Allows use of < instead of <=, less gas
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");


        return getBaseURI();
    }
    function wenSale() public view returns (string memory) {
        if(!isSaleOpen()) return "#soon";
        return isSaleComplete() ? "complete" : "now!";
    }

    function isSaleOpen() public view returns (bool) {
        return _saleState == 1;
    }

    function isSaleComplete() public view returns (bool) {
        return tokenCounter == _totalSupply;
    }
    
    function getSaleState() private view returns (uint){
        return _saleState;
    }
    
    function setSaleState(uint saleState) public onlyOwner {
        _saleState = saleState;
    }
    
    function getSalePrice() private view returns (uint){
        return _salePrice;
    }
    
    function setSalePrice(uint256 salePrice) public onlyOwner {
        _salePrice = salePrice;
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
