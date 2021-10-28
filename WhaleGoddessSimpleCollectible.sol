//"SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract SimpleCollectible is ERC721, Ownable {
    uint256 public tokenCounter;

    uint256 private _presalePrice = 0; //.00 ETH
    uint256 private _salePrice = 50000000000000000; // .05 ETH

    uint256 private _maxPerTx = 21; // Set to one higher than actual, to save gas on <= checks.

    uint256 public _presaleSupply = 100;
    uint256 public _totalSupply = 10000; 

    string private _baseTokenURI;
    uint private _saleState; // 0 - No sale. 1 - Presale. 2 - Main Sale.

    // Faciliating the needed functionality for the presale
    mapping(address => bool) addressToPreSaleEntry;
    
    constructor () ERC721 ("Test NFT","PERLIN")  {
        tokenCounter = 0;
        _saleState = 0;
    }

    function mintPresaleCollectibles(uint256 _count) public payable {
        require(isPresaleOpen(), "Presale is not yet open. See wenPresale and wenSale for more info");
        require(!isPresaleComplete(), "Presale is over. See wenSale for more info");

        require(isWalletInPresale(msg.sender), "Wallet isnt in presale! The owner needs to addWalletToPresale.");
        require((_count + tokenCounter) <= _presaleSupply, "Ran out of NFTs for presale! Sry!");
        require(msg.value >= (_presalePrice * _count), "Ether value sent is too low");

        createCollectibles(msg.sender, _count);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");


        return string(abi.encodePacked(getBaseURI(), Strings.toString(tokenId)));
    }
    function mintCollectibles(uint256 _count) public payable {
        require(isSaleOpen(), "Sale is not yet open");
        require(isPresaleComplete(), "Presale has not started or is ongoing");
        require(_count < _maxPerTx, "Cant mint more than mintMax");
        require((_count + tokenCounter) <= _totalSupply, "Ran out of NFTs for sale! Sry!");
        require(msg.value >= (_salePrice * _count), "Ether value sent is not correct");

        createCollectibles(msg.sender, _count);
    }

	function mintWithWGPass(address _user) public {
	    require(msg.sender == address(0xDF47D84787c4607Ad3c7034D2b238Beec2B0cf49), "Only the mint pass contract may call this function");
        require((1 + tokenCounter) <= _totalSupply, "Ran out of NFTs for sale! Sry!");
        
        createCollectibles(_user, 1);
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

    function wenPresale() public view returns (string memory) {
        if(!isPresaleOpen()) return "#soon";
        return isPresaleComplete() ? "complete" : "now!";
    }

    function wenSale() public view returns (string memory) {
        if(!isSaleOpen()) return "#soon";
        return isSaleComplete() ? "complete" : "now!";
    }

    function isSaleOpen() public view returns (bool) {
        return _saleState == 2;
    }

    function isSaleComplete() public view returns (bool) {
        return tokenCounter == _totalSupply;
    }
    function isPresaleOpen() public view returns (bool) {
        return _saleState >= 1;
    }
    function isPresaleComplete() public view returns (bool) {
        return tokenCounter >= _presaleSupply;
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
    
    function getPresalePrice() private view returns (uint){
        return _presalePrice;
    }

    function isWalletInPresale(address _address) public view returns (bool) {
        return addressToPreSaleEntry[_address];
    }
    function addWalletToPreSale(address _address) public onlyOwner {
        addressToPreSaleEntry[_address] = true;
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
